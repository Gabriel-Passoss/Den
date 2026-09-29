import Testing
import Foundation
@testable import DevSpace

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
        .appending(path: "run-configurations.json")
}

private func sampleCommand() -> RunConfiguration {
    RunConfiguration(name: "API", kind: .command(CommandSpec(
        command: "npm run dev", workingDirectory: "apps/api",
        environment: [EnvVar(key: "PORT", value: "3000")])))
}

@Test func aMissingFileLoadsAsEmpty() {
    #expect(RunConfigurationStore(url: temporaryFile()).load().isEmpty)
}

@Test func savedProjectsComeBackIntact() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = RunConfigurationStore(url: url)
    let api = sampleCommand()
    let everything = RunConfiguration(name: "Everything", kind: .compound([api.id]))

    let app = ProjectRoot(URL(fileURLWithPath: "/code/app"))
    try store.save([app: [api, everything]])

    #expect(store.load() == [app: [api, everything]])
}

@Test func theFileUsesAStableShape() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try RunConfigurationStore(url: url).save([ProjectRoot(URL(fileURLWithPath: "/code/app")): [sampleCommand()]])

    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let projects = try #require(object?["projects"] as? [String: Any])
    let first = try #require((projects["/code/app"] as? [[String: Any]])?.first)
    #expect(object?["version"] as? Int == 1)
    #expect(first["type"] as? String == "command")
    #expect((first["command"] as? [String: Any])?["command"] as? String == "npm run dev")
}

@Test func aCorruptFileIsSetAsideAndLoadsAsEmpty() throws {
    let url = temporaryFile()
    let folder = url.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{not json".utf8).write(to: url)

    #expect(RunConfigurationStore(url: url).load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let siblings = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(siblings.contains { $0.hasPrefix("run-configurations.corrupt-") })
}

@Test func resolvedDirectoryHandlesEmptyRelativeAndAbsolute() {
    let root = URL(fileURLWithPath: "/code/app")
    func spec(_ directory: String) -> CommandSpec {
        CommandSpec(command: "make", workingDirectory: directory, environment: [])
    }
    #expect(spec("").resolvedDirectory(in: root).path == "/code/app")
    #expect(spec(" apps/web ").resolvedDirectory(in: root).path == "/code/app/apps/web")
    #expect(spec("/elsewhere").resolvedDirectory(in: root).path == "/elsewhere")
    #expect(CommandSpec.directory("apps/web", in: root).path == "/code/app/apps/web")
}

@Test func aProjectRootIsTheSameWithOrWithoutATrailingSlash() {
    let plain = ProjectRoot(URL(fileURLWithPath: "/code/app"))
    let slashed = ProjectRoot(URL(fileURLWithPath: "/code/app/"))
    #expect(plain == slashed)
    #expect(Set([plain, slashed]).count == 1)
    #expect(plain.path == "/code/app")
}
