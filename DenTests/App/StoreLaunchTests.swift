import Testing
import Foundation
import HarnessCore
import DenStore
@testable import Den

private func scratchFile() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString).appending(path: "den.sqlite")
}

@Test func aLaunchOnAFreshFileOpensTheStore() async throws {
    let file = scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    let launch = StoreLaunch.open(file)

    #expect(launch.failure == nil)
    try await launch.repositories.sessions.saveMetadata(storedSession("Guardada"))
    #expect(try await StoreLaunch.open(file).repositories.sessions.list().map(\.title) == ["Guardada"])
}

@Test func aLaunchThatCannotOpenTheStoreSaysWhyAndHandsOutAnEmptyOne() async throws {
    let blocker = scratchFile()
    defer { try? FileManager.default.removeItem(at: blocker.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data("um arquivo comum".utf8).write(to: blocker)

    let launch = StoreLaunch.open(blocker.appending(path: "dentro/den.sqlite"))

    #expect(launch.failure?.hasPrefix("Não consegui abrir o banco de dados do Den") == true)
    #expect(try await launch.repositories.sessions.list().isEmpty)
}

@Test func aFailureIsExplainedInWords() {
    let newer = StoreLaunch.message(for: DenStoreError.newerSchema(found: 3, supported: 1))
    #expect(newer.contains("versão mais nova do Den"))
    #expect(newer.contains("esquema 3"))
    #expect(StoreLaunch.message(for: DenStoreError.unavailable("disco cheio"))
        == "Não consegui abrir o banco de dados do Den: disco cheio")
    #expect(StoreLaunch.message(for: CocoaError(.fileNoSuchFile))
        .hasPrefix("Não consegui abrir o banco de dados do Den: "))
}
