import Testing
import Foundation
@testable import HarnessCore
import HarnessTestSupport

private func shellLaunch(_ script: String) -> ProcessTransport.Launch {
    ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", script],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        environment: ProcessInfo.processInfo.environment
    )
}

private func floodScript(writers: Int) -> String {
    """
    pad=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    i=0; while [ $i -lt 7 ]; do pad="$pad$pad"; i=$((i+1)); done
    n=0
    while [ $n -lt \(writers) ]; do
      ( while :; do printf '%s\\n' "$pad"; done ) &
      n=$((n+1))
    done
    printf '{"a":1}\\n'
    """
}

@Test func readsTheLinesTheProcessEmits() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch(#"printf '{"a":1}\n{"b":2}\n'"#))

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received == [#"{"a":1}"#, #"{"b":2}"#])
    }
}

@Test func capturesStandardError() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch(#"echo aviso >&2; printf '{"a":1}\n'"#))
        for try await _ in stream {}
        let stderr = await transport.standardError
        #expect(stderr.contains("aviso"))
    }
}

@Test func writesToStdinAndTheProcessResponds() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()

        let stream = try await transport.start(
            shellLaunch(#"while read -r l; do printf '{"echo":%s}\n' "$l"; done"#)
        )

        try await transport.write(Data(#"{"a":1}"#.utf8))
        try await transport.write(Data(#"{"b":2}"#.utf8))
        await transport.endInput()

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received == [#"{"echo":{"a":1}}"#, #"{"echo":{"b":2}}"#])
    }
}

@Test func recordsTheExitCode() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch("exit 3"))
        for try await _ in stream {}
        let status = await transport.terminationStatus
        #expect(status == 3)
    }
}

@Test func terminateReapsImmediatelyAProcessThatObeysSIGTERM() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch("sleep 60"))
        let started = ContinuousClock.now
        await transport.terminate()
        for try await _ in stream {}
        let status = await transport.terminationStatus
        #expect(status != nil)

        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

@Test func terminateEscalatesToSIGKILLWhenSIGTERMIsIgnored() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport(
            terminationGracePeriod: .milliseconds(50),
            killGracePeriod: .milliseconds(30)
        )
        let stream = try await transport.start(
            shellLaunch(#"trap "" TERM; printf '{"armed":1}\n'; read x"#)
        )

        var iterator = stream.makeAsyncIterator()
        let armed = try await iterator.next()
        #expect(armed.map { String(decoding: $0, as: UTF8.self) } == #"{"armed":1}"#)

        await transport.terminate()
        while try await iterator.next() != nil {}

        #expect(await transport.terminationStatus == SIGKILL)
    }
}

@Test func startRefusesASecondUseOfTheSameTransport() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch("sleep 60"))

        await #expect(throws: ProcessTransport.TransportError.alreadyStarted) {
            _ = try await transport.start(shellLaunch("exit 0"))
        }

        await transport.terminate()
        for try await _ in stream {}

        #expect(await transport.terminationStatus == SIGTERM)
    }
}

@Test func aFailedStartDoesNotBurnTheTransport() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        var quebrado = shellLaunch("exit 0")
        quebrado.executable = "/nao/existe/harness"

        await #expect(throws: (any Error).self) {
            _ = try await transport.start(quebrado)
        }

        let stream = try await transport.start(shellLaunch(#"printf '{"a":1}\n'"#))
        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received == [#"{"a":1}"#])
    }
}

@Test func propagatesAFramingError() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport(framingLimit: 16)
        let stream = try await transport.start(shellLaunch(#"printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'"#))
        await #expect(throws: NDJSONFramer.FramingError.self) {
            for try await _ in stream {}
        }
    }
}

@Test func aFramingErrorTearsTheProcessDown() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport(framingLimit: 16)
        let stream = try await transport.start(
            shellLaunch(#"printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; sleep 30"#)
        )
        await #expect(throws: NDJSONFramer.FramingError.self) {
            for try await _ in stream {}
        }

        var status: Int32?
        for _ in 0..<100 {
            status = await transport.terminationStatus
            if status != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(status != nil)
    }
}

@Test func failsToLaunchAnExecutableThatDoesNotExist() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        var launch = shellLaunch("exit 0")
        launch.executable = "/nao/existe/harness"

        await #expect(throws: (any Error).self) {
            _ = try await transport.start(launch)
        }
        let status = await transport.terminationStatus
        #expect(status == nil)
    }
}

@Test func doesNotLoseLinesFromABurstThatEndsImmediately() async throws {
    try await withTimeout(seconds: 10) {
        let transport = ProcessTransport()
        let stream = try await transport.start(
            shellLaunch(#"i=1; while [ $i -le 2000 ]; do printf '{"n":%d}\n' "$i"; i=$((i+1)); done"#)
        )

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received.count == 2000)
        #expect(received.first == #"{"n":1}"#)
        #expect(received.last == #"{"n":2000}"#)
    }
}

@Test func endsTheStreamWithoutWaitingForAGrandchildHoldingThePipes() async throws {
    try await withTimeout(seconds: 3) {
        let transport = ProcessTransport()
        let stream = try await transport.start(
            shellLaunch(#"(sleep 5) & printf '{"a":1}\n'"#)
        )

        let started = ContinuousClock.now
        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received == [#"{"a":1}"#])
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

@Test func endsTheStreamWithAGrandchildThatKeepsWriting() async throws {
    try await withTimeout(seconds: 3) {
        let transport = ProcessTransport()

        let stream = try await transport.start(shellLaunch(floodScript(writers: 16)))

        let started = ContinuousClock.now
        var received = 0
        for try await _ in stream { received += 1 }

        #expect(received > 0)
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

@Test func theFinalSweepIsBounded() async throws {
    try await withTimeout(seconds: 10) {
        let target = Pipe()
        let flooder = Process()
        flooder.executableURL = URL(fileURLWithPath: "/bin/sh")
        flooder.arguments = ["-c", floodScript(writers: 32)]
        flooder.standardOutput = target
        try flooder.run()
        defer { flooder.terminate() }

        let ceiling = StreamIO.sweepByteLimit + StreamIO.sweepReadSize
        for _ in 0..<6 {

            try await Task.sleep(for: .milliseconds(5))
            let swept = StreamIO.readPending(target.fileHandleForReading)
            #expect(swept.count <= ceiling)
        }
    }
}

@Test func drainsStderrContinuouslyWhileStdoutFlows() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()

        let stream = try await transport.start(shellLaunch("""
            pad=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
            i=0; while [ $i -lt 7 ]; do pad="$pad$pad"; i=$((i+1)); done
            i=1
            while [ $i -le 100 ]; do
              printf '%s\\n' "$pad" >&2
              printf '{"n":%d}\\n' "$i"
              i=$((i+1))
            done
            """))

        var received: [String] = []
        for try await line in stream {
            received.append(String(decoding: line, as: UTF8.self))
        }
        #expect(received.count == 100)
        #expect(received.first == #"{"n":1}"#)
        #expect(received.last == #"{"n":100}"#)

        let stderr = await transport.standardError
        #expect(stderr.count >= 100 * 4096)
    }
}

@Test func writingAfterTheChildClosedStdinFailsWithoutKillingTheParent() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()

        let stream = try await transport.start(
            shellLaunch(#"exec 0<&-; printf '{"ready":1}\n'; sleep 5"#)
        )

        var iterator = stream.makeAsyncIterator()
        let ready = try await iterator.next()
        #expect(ready.map { String(decoding: $0, as: UTF8.self) } == #"{"ready":1}"#)

        await #expect(throws: (any Error).self) {
            try await transport.write(Data(#"{"a":1}"#.utf8))
        }
        await transport.terminate()
    }
}

@Test func writeSyncReachesTheChildWithoutSuspending() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(
            shellLaunch(#"while read -r l; do printf '{"eco":%s}\n' "$l"; done"#)
        )
        try transport.writeSync(Data(#"{"a":1}"#.utf8))
        await transport.endInput()

        var received: [String] = []
        for try await line in stream { received.append(String(decoding: line, as: UTF8.self)) }
        #expect(received == [#"{"eco":{"a":1}}"#])
    }
}

@Test func writeSyncFailsAfterInputIsClosed() async throws {
    try await withTimeout(seconds: 5) {
        let transport = ProcessTransport()
        let stream = try await transport.start(shellLaunch("cat > /dev/null"))
        await transport.endInput()
        #expect(throws: ProcessTransport.TransportError.notRunning) {
            try transport.writeSync(Data("{}".utf8))
        }
        for try await _ in stream {}
    }
}

@Test func concurrentWritersDoNotInterleaveOnThePipe() async throws {
    try await withTimeout(seconds: 20) {
        let transport = ProcessTransport()

        let stream = try await transport.start(shellLaunch("cat"))

        let lineSize = 100_000
        let rounds = 3
        let writersPerPath = 4
        let viaActor = Data(repeating: UInt8(ascii: "x"), count: lineSize)
        let viaSync = Data(repeating: UInt8(ascii: "y"), count: lineSize)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<writersPerPath {
                group.addTask { for _ in 0..<rounds { try await transport.write(viaActor) } }
                group.addTask { for _ in 0..<rounds { try transport.writeSync(viaSync) } }
            }
            try await group.waitForAll()
        }
        await transport.endInput()

        var lines: [Data] = []
        for try await line in stream { lines.append(line) }

        #expect(lines.count == rounds * writersPerPath * 2)
        #expect(lines.allSatisfy { $0.count == lineSize })
        #expect(lines.allSatisfy { line in
            line.allSatisfy { $0 == UInt8(ascii: "x") } || line.allSatisfy { $0 == UInt8(ascii: "y") }
        })
    }
}
