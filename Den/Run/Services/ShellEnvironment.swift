import Darwin
import Foundation

actor ShellEnvironment {
    nonisolated struct Resolved: Equatable, Sendable {
        var shell: String
        var variables: [String: String]
        var warning: String?
    }

    typealias Probe = @Sendable (_ shell: String, _ arguments: [String], _ timeout: Duration) async -> Data?

    nonisolated static let marker = "__DEN_ENV__"
    nonisolated static let fallbackWarning =
        "Não consegui carregar o ambiente do seu shell; usando o PATH padrão"
    nonisolated private static let dropped: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_"]

    nonisolated let shell: String
    private let base: [String: String]
    private let timeout: Duration
    private let probe: Probe
    private var resolution: Task<Resolved, Never>?

    init(shell: String = ShellEnvironment.loginShell(),
         base: [String: String] = ProcessInfo.processInfo.environment,
         timeout: Duration = .seconds(5),
         probe: @escaping Probe = ShellProbe.run) {
        self.shell = shell
        self.base = base
        self.timeout = timeout
        self.probe = probe
    }

    func resolve() async -> Resolved {
        if let resolution { return await resolution.value }
        let task = Task { [shell, base, timeout, probe] in
            let arguments = ["-l", "-i", "-c", "echo \(Self.marker); /usr/bin/env -0"]
            if let output = await probe(shell, arguments, timeout),
               let variables = Self.parse(output), variables["PATH"] != nil {
                return Resolved(shell: shell, variables: variables, warning: nil)
            }
            return Resolved(shell: shell, variables: Self.fallback(from: base),
                            warning: Self.fallbackWarning)
        }
        resolution = task
        return await task.value
    }

    nonisolated static func parse(_ output: Data) -> [String: String]? {
        guard let range = output.range(of: Data((marker + "\n").utf8)) else { return nil }
        var variables: [String: String] = [:]
        for entry in output[range.upperBound...].split(separator: 0) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let equals = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equals])
            guard !key.isEmpty, !dropped.contains(key) else { continue }
            variables[key] = String(text[text.index(after: equals)...])
        }
        return variables
    }

    nonisolated static func fallback(from base: [String: String]) -> [String: String] {
        var result = base.filter { !dropped.contains($0.key) }
        let current = (result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        let extra = ["/opt/homebrew/bin", "/usr/local/bin"].filter { !current.contains($0) }
        result["PATH"] = (extra + current).joined(separator: ":")
        return result
    }

    nonisolated static func defaultLocale(
        identifier: String = Locale.current.identifier,
        isInstalled: (String) -> Bool = { FileManager.default.fileExists(atPath: "/usr/share/locale/\($0)") }
    ) -> String {
        let base = identifier.split(separator: "@").first.map(String.init) ?? identifier
        let candidate = base + ".UTF-8"
        return isInstalled(candidate) ? candidate : "en_US.UTF-8"
    }

    nonisolated static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let path = String(cString: raw)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }
}

extension ShellEnvironment.Resolved {
    nonisolated func processEnvironment(overrides: [EnvVar],
                                        locale: String = ShellEnvironment.defaultLocale()) -> [String: String] {
        var result = variables
        result["TERM"] = "xterm-256color"
        result["COLORTERM"] = "truecolor"
        if result["LANG"] == nil, result["LC_ALL"] == nil, result["LC_CTYPE"] == nil {
            result["LANG"] = locale
        }
        for variable in overrides {
            let key = variable.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.contains("=") else { continue }
            result[key] = variable.value
        }
        return result
    }
}

nonisolated enum ShellProbe {
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var ended = false

        func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
        func end() { lock.withLock { ended = true } }
        var isEnded: Bool { lock.withLock { ended } }
        var collected: Data { lock.withLock { data } }
    }

    static func run(shell: String, arguments: [String], timeout: Duration) async -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let collector = Collector()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                collector.end()
            } else {
                collector.append(chunk)
            }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let deadline = ContinuousClock.now + timeout
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !process.isRunning else {
            kill(process.processIdentifier, SIGKILL)
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        let drainDeadline = ContinuousClock.now + .milliseconds(500)
        while !collector.isEnded, ContinuousClock.now < drainDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        return collector.collected
    }
}
