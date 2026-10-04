import Darwin
import Foundation

nonisolated struct LaunchRequest: Equatable, Sendable {
    var shell: String
    var command: String
    var directory: URL
    var environment: [String: String]
}

nonisolated enum ProcessExit: Equatable, Sendable {
    case code(Int32)
    case signal(Int32)

    init(waitStatus: Int32) {
        let signal = waitStatus & 0x7F
        self = signal == 0 ? .code((waitStatus >> 8) & 0xFF) : .signal(signal)
    }
}

nonisolated enum LaunchError: Error, Equatable {
    case terminalUnavailable(Int32)
    case spawnFailed(Int32)

    var message: String {
        switch self {
        case .terminalUnavailable(let code):
            "Não consegui abrir um terminal para o processo: \(String(cString: strerror(code)))"
        case .spawnFailed(let code):
            "Não consegui iniciar o processo: \(String(cString: strerror(code)))"
        }
    }
}

nonisolated protocol RunningProcess: AnyObject, Sendable {
    var pid: Int32 { get }
    func terminate(grace: Duration) async
}

nonisolated protocol ProcessLaunching: Sendable {
    func launch(_ request: LaunchRequest,
                onOutput: @escaping @Sendable (Data) -> Void,
                onExit: @escaping @Sendable (ProcessExit) -> Void) throws -> any RunningProcess
}

nonisolated struct PTYLauncher: ProcessLaunching {
    func launch(_ request: LaunchRequest,
                onOutput: @escaping @Sendable (Data) -> Void,
                onExit: @escaping @Sendable (ProcessExit) -> Void) throws -> any RunningProcess {
        try PTYProcess.spawn(request, onOutput: onOutput, onExit: onExit)
    }
}

nonisolated final class PTYProcess: RunningProcess, @unchecked Sendable {
    static let columns: UInt16 = 160
    static let rows: UInt16 = 50

    static let guardScript = """
        exec 3<&0
        (cat <&3; trap '' TERM INT HUP; kill -TERM -$$; sleep 3; kill -KILL -$$) >/dev/null 2>&1 &
        exec 3<&-
        exec "$0" -c "$1"
        """

    static func arguments(for request: LaunchRequest) -> [String] {
        ["/bin/sh", "-c", guardScript, request.shell, request.command]
    }

    let pid: Int32
    private let hostEnd: Int32
    private let input: Int32
    private let queue: DispatchQueue
    private let onOutput: @Sendable (Data) -> Void
    private let onExit: @Sendable (ProcessExit) -> Void
    private let lock = NSLock()
    private var exited = false
    private var reaped = false
    private var readOpen = true
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private var buffer = [UInt8](repeating: 0, count: 65_536)

    private init(pid: Int32, hostEnd: Int32, input: Int32,
                 onOutput: @escaping @Sendable (Data) -> Void,
                 onExit: @escaping @Sendable (ProcessExit) -> Void) {
        self.pid = pid
        self.hostEnd = hostEnd
        self.input = input
        self.queue = DispatchQueue(label: "Den.PTYProcess.\(pid)", qos: .userInitiated)
        self.onOutput = onOutput
        self.onExit = onExit
    }

    var hasExited: Bool { lock.withLock { exited } }

    static func spawn(_ request: LaunchRequest,
                      onOutput: @escaping @Sendable (Data) -> Void,
                      onExit: @escaping @Sendable (ProcessExit) -> Void) throws -> PTYProcess {
        guard FileManager.default.isExecutableFile(atPath: request.shell) else {
            throw LaunchError.spawnFailed(ENOENT)
        }
        var hostEnd: Int32 = -1
        var childEnd: Int32 = -1
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&hostEnd, &childEnd, nil, nil, &size) == 0 else {
            throw LaunchError.terminalUnavailable(errno)
        }
        var inputPipe: [Int32] = [-1, -1]
        guard pipe(&inputPipe) == 0 else {
            let code = errno
            close(hostEnd)
            close(childEnd)
            throw LaunchError.terminalUnavailable(code)
        }
        for descriptor in [hostEnd, childEnd] + inputPipe {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT
            | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        var defaults = sigset_t()
        sigfillset(&defaults)
        sigdelset(&defaults, SIGKILL)
        sigdelset(&defaults, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inputPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, childEnd, 1)
        posix_spawn_file_actions_adddup2(&actions, childEnd, 2)
        posix_spawn_file_actions_addchdir(&actions, request.directory.path)

        let arguments = arguments(for: request)
        let environment = request.environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let result = withCStrings(arguments) { argv in
            withCStrings(environment) { envp in
                posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp)
            }
        }
        close(childEnd)
        close(inputPipe[0])
        guard result == 0 else {
            close(hostEnd)
            close(inputPipe[1])
            throw LaunchError.spawnFailed(result)
        }

        _ = fcntl(hostEnd, F_SETFL, fcntl(hostEnd, F_GETFL) | O_NONBLOCK)
        let process = PTYProcess(pid: pid, hostEnd: hostEnd, input: inputPipe[1],
                                 onOutput: onOutput, onExit: onExit)
        process.startMonitoring()
        return process
    }

    func terminate(grace: Duration) async {
        guard !isGone else { return }
        kill(-pid, SIGTERM)
        if await waitUntilGone(within: grace) { return }
        kill(-pid, SIGKILL)
        _ = await waitUntilGone(within: .seconds(2))
    }

    private var isGone: Bool {
        hasExited && kill(-pid, 0) != 0 && errno == ESRCH
    }

    private func waitUntilGone(within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            if isGone { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return isGone
    }

    private func startMonitoring() {
        let read = DispatchSource.makeReadSource(fileDescriptor: hostEnd, queue: queue)
        read.setEventHandler { self.drain() }
        read.setCancelHandler { close(self.hostEnd) }
        let exit = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        exit.setEventHandler { self.collect(blocking: true) }
        readSource = read
        exitSource = exit
        read.activate()
        exit.activate()
        queue.async { self.collect(blocking: false) }
    }

    private func drain() {
        while readOpen {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(hostEnd, $0.baseAddress, $0.count) }
            if count > 0 {
                onOutput(Data(buffer[0..<count]))
                continue
            }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN { return }
            readOpen = false
            readSource?.cancel()
        }
    }

    private func collect(blocking: Bool) {
        guard !reaped else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(pid, &status, blocking ? 0 : WNOHANG)
        } while result < 0 && errno == EINTR
        guard result != 0 else { return }
        reaped = true

        drain()
        if readOpen {
            readOpen = false
            readSource?.cancel()
        }
        exitSource?.cancel()
        close(input)
        onExit(result == pid ? ProcessExit(waitStatus: status) : .code(-1))
        lock.withLock { exited = true }
    }

    private static func withCStrings<R>(_ strings: [String],
                                        _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        let pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                preconditionFailure("the argument list always holds its nil terminator")
            }
            return body(base)
        }
    }
}
