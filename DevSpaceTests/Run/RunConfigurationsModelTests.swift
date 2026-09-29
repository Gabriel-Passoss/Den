import Testing
import Foundation
@testable import DevSpace

private func withModel(_ body: (RunConfigurationsModel, RunConfigurationStore) throws -> Void) rethrows {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RunConfigurationStore(url: folder.appending(path: "run-configurations.json"))
    try body(RunConfigurationsModel(store: store), store)
}

private func command(_ name: String) -> RunConfiguration {
    RunConfiguration(name: name, kind: .command(CommandSpec(
        command: "make \(name)", workingDirectory: "", environment: [])))
}

private let app = URL(fileURLWithPath: "/code/app")
private let other = URL(fileURLWithPath: "/code/other")

@Test func addedConfigurationsPersistPerProject() {
    withModel { model, store in
        let api = command("API")
        model.add(api, to: app)

        #expect(model.configurations(in: app) == [api])
        #expect(model.configurations(in: other).isEmpty)
        #expect(RunConfigurationsModel(store: store).configurations(in: app) == [api])
    }
}

@Test func updateReplacesInPlace() {
    withModel { model, _ in
        var api = command("API")
        let web = command("Web")
        model.add(api, to: app)
        model.add(web, to: app)

        api.name = "Backend"
        model.update(api, in: app)

        #expect(model.configurations(in: app).map(\.name) == ["Backend", "Web"])
    }
}

@Test func removingTheLastConfigurationDropsTheProject() {
    withModel { model, _ in
        let api = command("API")
        model.add(api, to: app)
        model.remove(api.id, from: app)

        #expect(model.projects[ProjectRoot(app)] == nil)
    }
}

@Test func removingAConfigurationTakesItOutOfCompounds() {
    withModel { model, _ in
        let api = command("API")
        let web = command("Web")
        let everything = RunConfiguration(name: "Everything", kind: .compound([api.id, web.id]))
        model.add(api, to: app)
        model.add(web, to: app)
        model.add(everything, to: app)

        model.remove(api.id, from: app)

        #expect(model.configurations(in: app).last?.kind == .compound([web.id]))
    }
}

@Test func namesMustBePresentAndUnique() {
    withModel { model, _ in
        let api = command("API")
        model.add(api, to: app)

        #expect(model.nameProblem(for: "  ", excluding: nil, in: app) == .empty)
        #expect(model.nameProblem(for: " api ", excluding: nil, in: app) == .duplicate)
        #expect(model.nameProblem(for: "API", excluding: api.id, in: app) == nil)
        #expect(model.nameProblem(for: "Web", excluding: nil, in: app) == nil)
        #expect(model.nameProblem(for: "API", excluding: nil, in: other) == nil)
    }
}

@Test func theProjectRootPrefersAFolderThatAlreadyHasConfigurations() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString).standardizedFileURL
    try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "api/src"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    withModel { model, _ in
        #expect(model.root(for: root.appending(path: "api/src")).path == root.path)

        model.add(command("API"), to: root.appending(path: "api"))

        #expect(model.root(for: root.appending(path: "api/src")).path == root.appending(path: "api").path)
    }
}
