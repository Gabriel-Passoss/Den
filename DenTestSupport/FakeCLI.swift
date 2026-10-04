import Foundation

nonisolated final class FakeCLI {
    struct Launch {
        let directory: String
        let arguments: [String]
    }

    let directory: URL
    let state: URL
    let executable: String
    private let scenarioKey: String?
    private var steps = 0

    convenience init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FakeCLI-" + UUID().uuidString)
        try self.init(directory: directory, state: directory,
                      executable: directory.appending(path: "cli").path, scenarioKey: nil)
        let wrapper = """
            #!/bin/sh
            FAKE_CLI_STATE='\(directory.path)' exec '\(Self.scripts.appending(path: "fake-cli").path)' "$@"

            """
        try wrapper.write(toFile: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable)
    }

    convenience init(appRoot root: URL, harness: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FakeCLI-" + UUID().uuidString)
        try self.init(directory: directory, state: root.appending(path: "cli/\(harness)"),
                      executable: Self.scripts.appending(path: harness).path,
                      scenarioKey: "FAKE_CLI_SCENARIO_"
                        + harness.uppercased().replacingOccurrences(of: "-", with: "_"))
    }

    private init(directory: URL, state: URL, executable: String, scenarioKey: String?) throws {
        self.directory = directory
        self.state = state
        self.executable = executable
        self.scenarioKey = scenarioKey
        try FileManager.default.createDirectory(at: directory.appending(path: "steps"),
                                                withIntermediateDirectories: true)
        try "1".write(to: directory.appending(path: "next"), atomically: true, encoding: .utf8)
    }

    func on(_ trigger: String, reply lines: [String]) throws {
        let step = try addStep(trigger)
        try lines.map { $0 + "\n" }.joined()
            .write(to: step.appendingPathExtension("reply"), atomically: true, encoding: .utf8)
    }

    func on(_ trigger: String, exit status: Int32, stderr: String) throws {
        let step = try addStep(trigger)
        try String(status).write(to: step.appendingPathExtension("exit"),
                                 atomically: true, encoding: .utf8)
        try stderr.write(to: step.appendingPathExtension("stderr"),
                         atomically: true, encoding: .utf8)
    }

    func answerTitles(with title: String) throws {
        try title.write(to: directory.appending(path: "title"), atomically: true, encoding: .utf8)
    }

    func answerSuggestions(with reply: String) throws {
        try reply.write(to: directory.appending(path: "reply"), atomically: true, encoding: .utf8)
    }

    var launchEnvironment: [String: String] {
        guard let scenarioKey else { return [:] }
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath } ?? []
        let base = directory.resolvingSymlinksInPath().path + "/"
        let lines = files.compactMap { file -> String? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            let name = file.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "")
            return name + " " + data.base64EncodedString()
        }
        return [scenarioKey: lines.joined(separator: "\n")]
    }

    var launches: [Launch] {
        let folder = state.appending(path: "launches")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap(Int.init).sorted().compactMap { number in
            guard let text = try? String(contentsOf: folder.appending(path: String(number)),
                                         encoding: .utf8) else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .dropLast().map(String.init)
            guard let first = lines.first else { return nil }
            return Launch(directory: first, arguments: Array(lines.dropFirst()))
        }
    }

    var received: [String] {
        guard let text = try? String(contentsOf: state.appending(path: "received"),
                                     encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map { $0.replacingOccurrences(of: #"\/"#, with: "/") }
            .filter { !$0.contains(#""subtype":"get_context_usage""#) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func addStep(_ trigger: String) throws -> URL {
        steps += 1
        let step = directory.appending(path: "steps/\(steps)")
        try trigger.write(to: step.appendingPathExtension("trigger"),
                          atomically: true, encoding: .utf8)
        return step
    }

    private static let scripts = testResources

    static var gh: String { scripts.appending(path: "gh").path }
}

extension FakeCLI {
    static let userTurn = #""type":"user""#

    static let permissionAnswer = #""type":"control_response""#

    static func request(_ method: String) -> String { #""method":"\#(method)""# }

    static let answer = #""result":"#
}

nonisolated enum RecordedSession {
    static func claude(_ name: String) throws -> [String] {
        try lines(of: name)
    }

    static func claudeWritePermission() throws -> (untilAsking: [String], afterAnswer: [String]) {
        let lines = try claude("permission-request")
        guard let asking = lines.firstIndex(where: { $0.contains(#""subtype":"can_use_tool""#) })
        else { throw CocoaError(.fileReadCorruptFile) }
        return (Array(lines[...asking]), Array(lines[(asking + 1)...]))
    }

    static func openCode(_ name: String) throws -> [String] {
        try lines(of: name)
    }

    private static func lines(of name: String) throws -> [String] {
        let file = testResources.appending(path: name + ".ndjson")
        return try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }
}

nonisolated private final class TestBundle {}

nonisolated private let testResources: URL = {
    guard let resources = Bundle(for: TestBundle.self).resourceURL else {
        preconditionFailure("the test bundle has no resource folder")
    }
    return resources
}()
