# Configurações de execução — Entrega 1: rodar e ver o log

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O usuário cria uma configuração (nome, comando, pasta) no painel
Execução, clica ▶ e vê o log colorido chegando ao vivo; ■ derruba o processo
com todos os filhos.

**Architecture:** Um pseudo-terminal próprio (`PTYProcess`, `posix_spawn` com
`POSIX_SPAWN_SETSID`) roda `$SHELL -c "<comando>"` com o ambiente resolvido do
shell do usuário. A saída passa por um `ANSIParser` fora da main thread, é
agrupada em lotes de ~60ms (`LogIntake`) e vira operações incrementais num
`LogBuffer`, que um `NSTextView` aplica sem redesenhar. `RunManager` e
`RunConfigurationsModel` vivem no `AppDelegate`, acima das conversas.

**Tech Stack:** Swift (modo 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`),
SwiftUI + AppKit (`NSTextView`), Darwin (`openpty`, `posix_spawn`,
`DispatchSource`), Swift Testing. Zero dependências.

**Spec:** `docs/superpowers/specs/2026-09-28-run-configurations-design.md`
(§2 modelo, §2.2 persistência, §2.3 descoberta do projeto, §4 execução,
§5.1 toolbar, §5.2 painel, §6 testes, §7 entrega 1)

## Global Constraints

- Código, identificadores, nomes de teste e fixtures em **inglês**; só texto
  que o usuário lê (UI, `print` no terminal) em **português**.
- Toda label visível começa com **maiúscula** só na primeira palavra
  ("Nova configuração", "Saiu com código 1").
- Comentários: o código do app praticamente não tem; não acrescentar
  comentários explicativos.
- Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), funções
  `@Test` livres no arquivo, como em `DevSpaceTests/Git/GitChangesModelTests.swift`.
- Tipos puros usados fora da main thread são marcados `nonisolated`
  (inclusive tipos aninhados), porque o target isola tudo em `MainActor` por
  padrão.
- Os grupos do Xcode são sincronizados com o disco
  (`PBXFileSystemSynchronizedRootGroup`): arquivo criado em `DevSpace/` ou
  `DevSpaceTests/` entra no target sozinho. Não editar o `project.pbxproj`.
- Sem asserções de tempo de relógio. Esperas nos testes são limites generosos
  (`waitUntil`), nunca "levou menos de X".
- **Não commitar.** O usuário commita quando pedir; cada tarefa termina com
  a suíte verde, não com commit.
- Rodar a suíte: `xcodebuild test -project DevSpace.xcodeproj -scheme DevSpaceTests -destination 'platform=macOS' -derivedDataPath "$DD" 2>&1 | grep -E "error:|failed|passed|TEST (SUCCEEDED|FAILED)" | tail -40`,
  com `DD` apontando para uma pasta fora do repositório.

## Review Focus

- **Comando que termina na hora** (`echo hi`, `seq 1 2000`): tudo que ele
  imprimiu antes de sair precisa estar no log, e o estado precisa dizer que
  terminou. Teste na Task 8 (`anInstantExitStillDeliversEverything`).
- **Reiniciar enquanto o processo antigo ainda fala**: saída e fim do processo
  antigo que chegam depois do ↻ não podem tocar o log nem o estado da execução
  nova. Teste na Task 9 (`startingARunningConfigurationRestartsIt`).
- **Caracteres multibyte e escapes cortados entre leituras** (o `➜` do vite,
  emojis, `ESC[3` + `1m`): o texto e a cor saem inteiros. Testes na Task 4.
- **Pastas com espaço e acento, valores com `=`**: o processo sobe na pasta
  certa e `DATABASE_URL=a=b` chega intacto. Teste na Task 8
  (`theWorkingDirectoryAndEnvironmentAreApplied`) e na Task 7
  (`parseKeepsEverythingAfterTheFirstEquals`).
- **Shell que imprime saudação ou trava no `.zshrc`**: o ambiente ainda é
  lido depois do marcador; um shell travado cai no fallback em vez de
  congelar o ▶. Testes na Task 7.

---

### Task 1: `GitRepository` extraído e `RunProjectLocator`

**Files:**
- Create: `DevSpace/Git/Services/GitRepository.swift`
- Modify: `DevSpace/Git/GitChangesModel.swift` (a subida procurando `.git` no começo de `discoverRepoRoots`)
- Create: `DevSpace/Run/Services/RunProjectLocator.swift`
- Test: `DevSpaceTests/Run/RunProjectLocatorTests.swift`

**Interfaces:**
- Produces: `GitRepository.toplevel(containing: URL) -> URL?`;
  `RunProjectLocator.root(for: URL, knownRoots: Set<String>) -> URL`.
  As chaves de `knownRoots` são `URL.standardizedFileURL.path`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DevSpace

private func makeTree(_ relativePaths: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for path in relativePaths {
        try FileManager.default.createDirectory(at: root.appending(path: path),
                                                withIntermediateDirectories: true)
    }
    return root.standardizedFileURL
}

@Test func toplevelClimbsToTheEnclosingRepo() throws {
    let root = try makeTree([".git", "api/src"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GitRepository.toplevel(containing: root.appending(path: "api/src"))?.path == root.path)
}

@Test func toplevelIsNilOutsideAnyRepo() throws {
    let root = try makeTree(["plain/folder"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GitRepository.toplevel(containing: root.appending(path: "plain/folder")) == nil)
}

@Test func aKnownAncestorWinsOverTheRepoRoot() throws {
    let root = try makeTree([".git", "api/src"])
    defer { try? FileManager.default.removeItem(at: root) }
    let api = root.appending(path: "api")
    let found = RunProjectLocator.root(for: root.appending(path: "api/src"),
                                       knownRoots: [api.standardizedFileURL.path])
    #expect(found.path == api.path)
}

@Test func theDirectoryItselfCanBeTheKnownRoot() throws {
    let root = try makeTree([".git", "api"])
    defer { try? FileManager.default.removeItem(at: root) }
    let api = root.appending(path: "api")
    #expect(RunProjectLocator.root(for: api, knownRoots: [api.standardizedFileURL.path]).path == api.path)
}

@Test func withoutKnownRootsTheRepoRootIsTheProject() throws {
    let root = try makeTree([".git", "api/src"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(RunProjectLocator.root(for: root.appending(path: "api/src"), knownRoots: []).path == root.path)
}

@Test func withoutRepoOrKnownRootsTheDirectoryIsTheProject() throws {
    let root = try makeTree(["loose/folder"])
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appending(path: "loose/folder")
    #expect(RunProjectLocator.root(for: folder, knownRoots: []).path == folder.path)
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run the suite command from Global Constraints.
Expected: build error `cannot find 'GitRepository' in scope`.

- [ ] **Step 3: Write `GitRepository`**

```swift
import Foundation

nonisolated enum GitRepository {
    static func toplevel(containing directory: URL) -> URL? {
        let manager = FileManager.default
        var probe = directory.standardizedFileURL
        while probe.pathComponents.count > 1 {
            if manager.fileExists(atPath: probe.appending(path: ".git").path) {
                return probe
            }
            probe = probe.deletingLastPathComponent()
        }
        return nil
    }
}
```

- [ ] **Step 4: Use it in `GitChangesModel.discoverRepoRoots`**

Replace the block that starts with `var toplevel: URL?` and ends with
`if let toplevel { roots.append(toplevel) }` by:

```swift
        if let toplevel = GitRepository.toplevel(containing: directory) {
            roots.append(toplevel)
        }
```

- [ ] **Step 5: Write `RunProjectLocator`**

```swift
import Foundation

nonisolated enum RunProjectLocator {
    static func root(for directory: URL, knownRoots: Set<String>) -> URL {
        let start = directory.standardizedFileURL
        var probe = start
        while true {
            if knownRoots.contains(probe.path) { return probe }
            guard probe.pathComponents.count > 1 else { break }
            probe = probe.deletingLastPathComponent()
        }
        return GitRepository.toplevel(containing: start) ?? start
    }
}
```

- [ ] **Step 6: Run the suite**

Expected: TEST SUCCEEDED, including the existing `discover…` tests in
`GitChangesModelTests.swift`.

---

### Task 2: `RunConfiguration` e `RunConfigurationStore`

**Files:**
- Create: `DevSpace/Run/Models/RunConfiguration.swift`
- Create: `DevSpace/Run/Services/RunConfigurationStore.swift`
- Test: `DevSpaceTests/Run/RunConfigurationStoreTests.swift`

**Interfaces:**
- Produces:
  - `RunConfiguration(id: UUID = UUID(), name: String, kind: RunConfiguration.Kind)`,
    `Kind.command(CommandSpec)`, `Kind.compound([UUID])`, `var command: CommandSpec?`
  - `CommandSpec(command: String, workingDirectory: String, environment: [EnvVar])`,
    `func resolvedDirectory(in root: URL) -> URL`
  - `EnvVar(id: UUID = UUID(), key: String, value: String)`
  - `RunConfigurationStore(url: URL)`, `static var live`, `func load() -> [String: [RunConfiguration]]`,
    `func save(_: [String: [RunConfiguration]]) throws`

- [ ] **Step 1: Write the failing tests**

```swift
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
    let everything = RunConfiguration(name: "Tudo", kind: .compound([api.id]))

    try store.save(["/code/app": [api, everything]])

    #expect(store.load() == ["/code/app": [api, everything]])
}

@Test func theFileUsesAStableShape() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try RunConfigurationStore(url: url).save(["/code/app": [sampleCommand()]])

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
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'RunConfigurationStore' in scope`.

- [ ] **Step 3: Write the model**

```swift
import Foundation

nonisolated struct RunConfiguration: Codable, Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case command(CommandSpec)
        case compound([UUID])
    }

    let id: UUID
    var name: String
    var kind: Kind

    init(id: UUID = UUID(), name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    var command: CommandSpec? {
        if case .command(let spec) = kind { return spec }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, command, members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        switch try container.decode(String.self, forKey: .type) {
        case "command":
            kind = .command(try container.decode(CommandSpec.self, forKey: .command))
        case "compound":
            kind = .compound(try container.decode([UUID].self, forKey: .members))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "unknown configuration type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        switch kind {
        case .command(let spec):
            try container.encode("command", forKey: .type)
            try container.encode(spec, forKey: .command)
        case .compound(let members):
            try container.encode("compound", forKey: .type)
            try container.encode(members, forKey: .members)
        }
    }
}

nonisolated struct CommandSpec: Codable, Equatable, Sendable {
    var command: String
    var workingDirectory: String
    var environment: [EnvVar]

    func resolvedDirectory(in root: URL) -> URL {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return root }
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed) }
        return root.appending(path: trimmed)
    }
}

nonisolated struct EnvVar: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}
```

- [ ] **Step 4: Write the store**

```swift
import Foundation

nonisolated struct RunConfigurationStore: Sendable {
    let url: URL

    static var live: RunConfigurationStore {
        RunConfigurationStore(url: URL.applicationSupportDirectory
            .appending(path: "DevSpace/run-configurations.json"))
    }

    private struct File: Codable {
        var version: Int
        var projects: [String: [RunConfiguration]]
    }

    func load() -> [String: [RunConfiguration]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            return try JSONDecoder().decode(File.self, from: data).projects
        } catch {
            setAside(because: error)
            return [:]
        }
    }

    func save(_ projects: [String: [RunConfiguration]]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(File(version: 1, projects: projects)).write(to: url, options: .atomic)
    }

    private func setAside(because error: Error) {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingLastPathComponent()
            .appending(path: "run-configurations.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: target)
        print("configurações de execução ilegíveis em \(url.path): \(error)")
    }
}
```

- [ ] **Step 5: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 3: `RunConfigurationsModel`

**Files:**
- Create: `DevSpace/Run/RunConfigurationsModel.swift`
- Test: `DevSpaceTests/Run/RunConfigurationsModelTests.swift`

**Interfaces:**
- Consumes: `RunConfigurationStore`, `RunProjectLocator`, `RunConfiguration`.
- Produces: `RunConfigurationsModel(store:)`, `projects`, `root(for:) -> URL`,
  `configurations(in:) -> [RunConfiguration]`, `add(_:to:)`, `update(_:in:)`,
  `remove(_:from:)`, `nameProblem(for:excluding:in:) -> NameProblem?`,
  `NameProblem.empty / .duplicate`, `static func key(_ root: URL) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
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

        #expect(model.projects[RunConfigurationsModel.key(app)] == nil)
    }
}

@Test func removingAConfigurationTakesItOutOfCompounds() {
    withModel { model, _ in
        let api = command("API")
        let web = command("Web")
        let everything = RunConfiguration(name: "Tudo", kind: .compound([api.id, web.id]))
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
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'RunConfigurationsModel' in scope`.

- [ ] **Step 3: Write the model**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class RunConfigurationsModel {
    nonisolated enum NameProblem: Equatable {
        case empty
        case duplicate
    }

    private(set) var projects: [String: [RunConfiguration]]

    @ObservationIgnored private let store: RunConfigurationStore

    init(store: RunConfigurationStore) {
        self.store = store
        self.projects = store.load()
    }

    nonisolated static func key(_ root: URL) -> String {
        root.standardizedFileURL.path
    }

    func root(for directory: URL) -> URL {
        let known = Set(projects.filter { !$0.value.isEmpty }.keys)
        return RunProjectLocator.root(for: directory, knownRoots: known)
    }

    func configurations(in root: URL) -> [RunConfiguration] {
        projects[Self.key(root)] ?? []
    }

    func add(_ configuration: RunConfiguration, to root: URL) {
        projects[Self.key(root), default: []].append(configuration)
        persist()
    }

    func update(_ configuration: RunConfiguration, in root: URL) {
        let key = Self.key(root)
        guard let index = projects[key]?.firstIndex(where: { $0.id == configuration.id }) else { return }
        projects[key]?[index] = configuration
        persist()
    }

    func remove(_ id: UUID, from root: URL) {
        let key = Self.key(root)
        var list = projects[key] ?? []
        list.removeAll { $0.id == id }
        for index in list.indices {
            if case .compound(let members) = list[index].kind {
                list[index].kind = .compound(members.filter { $0 != id })
            }
        }
        projects[key] = list.isEmpty ? nil : list
        persist()
    }

    func nameProblem(for name: String, excluding id: UUID?, in root: URL) -> NameProblem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        let clash = configurations(in: root).contains {
            $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return clash ? .duplicate : nil
    }

    private func persist() {
        do {
            try store.save(projects)
        } catch {
            print("não consegui salvar as configurações de execução: \(error)")
        }
    }
}
```

- [ ] **Step 4: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 4: `LogStyle`/`LogLine` e `ANSIParser`

**Files:**
- Create: `DevSpace/Run/Models/LogLine.swift`
- Create: `DevSpace/Run/Services/ANSIParser.swift`
- Test: `DevSpaceTests/Run/ANSIParserTests.swift`

**Interfaces:**
- Produces:
  - `LogColor.palette(UInt8)`, `LogColor.rgb(UInt8, UInt8, UInt8)`
  - `LogStyle(foreground:background:bold:dim:italic:underline:inverse:)`, todos com
    padrão; `static let notice` (amarelo)
  - `LogSpan(text:style:)`, `LogLine(spans:)`, `LogLine.text`,
    `mutating func LogLine.append(_ text: String, style: LogStyle)`
  - `ANSIParser()`, `mutating feed(_ data: Data) -> [ANSIParser.Event]`,
    `mutating finish() -> [ANSIParser.Event]`,
    `Event.text(String, LogStyle) / .newline / .carriageReturn / .eraseToEnd / .eraseLine`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DevSpace

private let plain = LogStyle()
private let red = LogStyle(foreground: .palette(1))
private let green = LogStyle(foreground: .palette(2))

private func parse(_ chunks: [String]) -> [ANSIParser.Event] {
    parse(bytes: chunks.map { Array($0.utf8) })
}

private func parse(bytes chunks: [[UInt8]]) -> [ANSIParser.Event] {
    var parser = ANSIParser()
    return chunks.flatMap { parser.feed(Data($0)) } + parser.finish()
}

@Test func plainTextAndNewlinesBecomeEvents() {
    #expect(parse(["hello\nworld"]) == [.text("hello", plain), .newline, .text("world", plain)])
}

@Test func carriageReturnIsItsOwnEvent() {
    #expect(parse(["a\r\n"]) == [.text("a", plain), .carriageReturn, .newline])
}

@Test func sgrColorsTheFollowingText() {
    #expect(parse(["\u{1B}[31mred\u{1B}[0m plain"]) == [.text("red", red), .text(" plain", plain)])
}

@Test func anEmptySGRResets() {
    #expect(parse(["\u{1B}[31mA\u{1B}[mB"]) == [.text("A", red), .text("B", plain)])
}

@Test func brightAndBackgroundColorsMapToThePalette() {
    let style = LogStyle(foreground: .palette(10), background: .palette(4))
    #expect(parse(["\u{1B}[92;44mx"]) == [.text("x", style)])
}

@Test func extendedColorsCover256AndTruecolor() {
    #expect(parse(["\u{1B}[38;5;208ma\u{1B}[48;2;1;2;3mb"]) == [
        .text("a", LogStyle(foreground: .palette(208))),
        .text("b", LogStyle(foreground: .palette(208), background: .rgb(1, 2, 3))),
    ])
}

@Test func defaultColorCodesClearOnlyTheirChannel() {
    #expect(parse(["\u{1B}[31;42mA\u{1B}[39mB"]) == [
        .text("A", LogStyle(foreground: .palette(1), background: .palette(2))),
        .text("B", LogStyle(background: .palette(2))),
    ])
}

@Test func attributesToggleOnAndOff() {
    #expect(parse(["\u{1B}[1;2;3;4;7mA\u{1B}[22;23;24;27mB"]) == [
        .text("A", LogStyle(bold: true, dim: true, italic: true, underline: true, inverse: true)),
        .text("B", plain),
    ])
}

@Test func stylePersistsAcrossChunks() {
    #expect(parse(["\u{1B}[32m", "go"]) == [.text("go", green)])
}

@Test func anEscapeSplitAcrossChunksStillApplies() {
    #expect(parse(["\u{1B}[3", "1mred"]) == [.text("red", red)])
}

@Test func aMultibyteCharacterSplitAcrossChunksSurvives() {
    let bytes = Array("➜ ok".utf8)
    #expect(parse(bytes: [Array(bytes[0..<1]), Array(bytes[1...])]) == [.text("➜ ok", plain)])
    #expect(parse(bytes: [Array(bytes[0..<2]), Array(bytes[2...])]) == [.text("➜ ok", plain)])
}

@Test func eraseSequencesBecomeEvents() {
    #expect(parse(["a\u{1B}[Kb\u{1B}[0Kc\u{1B}[2Kd"]) == [
        .text("a", plain), .eraseToEnd, .text("b", plain), .eraseToEnd,
        .text("c", plain), .eraseLine, .text("d", plain),
    ])
}

@Test func cursorToColumnOneActsLikeACarriageReturn() {
    #expect(parse(["a\u{1B}[1Gb\u{1B}[Gc"]) == [
        .text("a", plain), .carriageReturn, .text("b", plain), .carriageReturn, .text("c", plain),
    ])
}

@Test func otherControlSequencesAreDropped() {
    let noisy = "\u{1B}[?25l\u{1B}[2J\u{1B}[3Ahi\u{1B}]0;title\u{07}!"
        + "\u{1B}]8;;http://x\u{1B}\\link\u{1B}]8;;\u{1B}\\\u{1B}(B."
    #expect(parse([noisy]) == [.text("hi!link.", plain)])
}

@Test func strayControlBytesAreDroppedButTabsStay() {
    #expect(parse(["a\u{07}\tb\u{08}"]) == [.text("a\tb", plain)])
}

@Test func finishFlushesATruncatedCharacterAsAReplacement() {
    #expect(parse(bytes: [[0x61, 0xE2]]) == [.text("a", plain), .text("\u{FFFD}", plain)])
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'ANSIParser' in scope`.

- [ ] **Step 3: Write the log line types**

```swift
import Foundation

nonisolated enum LogColor: Hashable, Sendable {
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

nonisolated struct LogStyle: Hashable, Sendable {
    var foreground: LogColor? = nil
    var background: LogColor? = nil
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var inverse = false

    static let notice = LogStyle(foreground: .palette(3))
}

nonisolated struct LogSpan: Equatable, Sendable {
    var text: String
    var style: LogStyle
}

nonisolated struct LogLine: Equatable, Sendable {
    var spans: [LogSpan] = []

    var text: String { spans.map(\.text).joined() }

    mutating func append(_ text: String, style: LogStyle) {
        guard !text.isEmpty else { return }
        if let last = spans.indices.last, spans[last].style == style {
            spans[last].text += text
        } else {
            spans.append(LogSpan(text: text, style: style))
        }
    }
}
```

- [ ] **Step 4: Write the parser**

```swift
import Foundation

nonisolated struct ANSIParser {
    nonisolated enum Event: Equatable, Sendable {
        case text(String, LogStyle)
        case newline
        case carriageReturn
        case eraseToEnd
        case eraseLine
    }

    private enum State {
        case ground, escape, escapeIntermediate, csi, osc, oscEscape
    }

    private(set) var style = LogStyle()
    private var state = State.ground
    private var pendingText: [UInt8] = []
    private var parameters: [UInt8] = []
    private var events: [Event] = []

    mutating func feed(_ data: Data) -> [Event] {
        for byte in data { consume(byte) }
        flushText(keepingIncomplete: true)
        return takeEvents()
    }

    mutating func finish() -> [Event] {
        flushText(keepingIncomplete: false)
        return takeEvents()
    }

    private mutating func takeEvents() -> [Event] {
        let taken = events
        events = []
        return taken
    }

    private mutating func consume(_ byte: UInt8) {
        switch state {
        case .ground:
            ground(byte)
        case .escape:
            switch byte {
            case 0x5B:
                parameters = []
                state = .csi
            case 0x5D:
                state = .osc
            case 0x20...0x2F:
                state = .escapeIntermediate
            default:
                state = .ground
            }
        case .escapeIntermediate:
            if !(0x20...0x2F).contains(byte) { state = .ground }
        case .csi:
            switch byte {
            case 0x30...0x3F:
                parameters.append(byte)
            case 0x40...0x7E:
                dispatchCSI(final: byte)
                state = .ground
            default:
                break
            }
        case .osc:
            if byte == 0x07 {
                state = .ground
            } else if byte == 0x1B {
                state = .oscEscape
            }
        case .oscEscape:
            state = byte == 0x5C ? .ground : .osc
        }
    }

    private mutating func ground(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            flushText(keepingIncomplete: false)
            state = .escape
        case 0x0A:
            flushText(keepingIncomplete: false)
            events.append(.newline)
        case 0x0D:
            flushText(keepingIncomplete: false)
            events.append(.carriageReturn)
        case 0x09:
            pendingText.append(byte)
        case 0x00..<0x20, 0x7F:
            break
        default:
            pendingText.append(byte)
        }
    }

    private mutating func dispatchCSI(final: UInt8) {
        if let first = parameters.first, (0x3C...0x3F).contains(first) { return }
        let values = parameters
            .split(omittingEmptySubsequences: false) { $0 == 0x3B || $0 == 0x3A }
            .map { Int(String(decoding: $0, as: UTF8.self)) }
        let first = values.first.flatMap { $0 }
        switch final {
        case 0x6D:
            applySGR(values.map { $0 ?? 0 })
        case 0x4B:
            events.append(first == nil || first == 0 ? .eraseToEnd : .eraseLine)
        case 0x47:
            if (first ?? 1) <= 1 { events.append(.carriageReturn) }
        default:
            break
        }
    }

    private mutating func applySGR(_ codes: [Int]) {
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = LogStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22:
                style.bold = false
                style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .palette(UInt8(code - 30))
            case 39: style.foreground = nil
            case 40...47: style.background = .palette(UInt8(code - 40))
            case 49: style.background = nil
            case 90...97: style.foreground = .palette(UInt8(code - 90 + 8))
            case 100...107: style.background = .palette(UInt8(code - 100 + 8))
            case 38, 48:
                let (color, consumed) = Self.extendedColor(codes, after: index)
                if let color {
                    if code == 38 { style.foreground = color } else { style.background = color }
                }
                index += consumed
            default:
                break
            }
            index += 1
        }
    }

    private static func extendedColor(_ codes: [Int], after index: Int) -> (LogColor?, Int) {
        guard index + 1 < codes.count else { return (nil, 0) }
        switch codes[index + 1] {
        case 5:
            guard index + 2 < codes.count else { return (nil, 1) }
            return (.palette(clamp(codes[index + 2])), 2)
        case 2:
            guard index + 4 < codes.count else { return (nil, codes.count - index - 1) }
            return (.rgb(clamp(codes[index + 2]), clamp(codes[index + 3]), clamp(codes[index + 4])), 4)
        default:
            return (nil, 1)
        }
    }

    private static func clamp(_ value: Int) -> UInt8 {
        UInt8(max(0, min(255, value)))
    }

    private mutating func flushText(keepingIncomplete: Bool) {
        guard !pendingText.isEmpty else { return }
        let cut = keepingIncomplete ? Self.completeLength(pendingText) : pendingText.count
        guard cut > 0 else { return }
        let text = String(decoding: pendingText[..<cut], as: UTF8.self)
        pendingText.removeFirst(cut)
        if case .text(let previous, let previousStyle)? = events.last, previousStyle == style {
            events[events.count - 1] = .text(previous + text, style)
        } else {
            events.append(.text(text, style))
        }
    }

    static func completeLength(_ bytes: [UInt8]) -> Int {
        var index = bytes.count - 1
        var continuation = 0
        while index >= 0, continuation < 3, bytes[index] & 0xC0 == 0x80 {
            continuation += 1
            index -= 1
        }
        guard index >= 0 else { return bytes.count }
        let expected: Int
        switch bytes[index] {
        case 0xC0...0xDF: expected = 2
        case 0xE0...0xEF: expected = 3
        case 0xF0...0xF7: expected = 4
        default: return bytes.count
        }
        return continuation + 1 < expected ? index : bytes.count
    }
}
```

- [ ] **Step 5: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 5: `LogBuffer`

**Files:**
- Create: `DevSpace/Run/Models/LogBuffer.swift`
- Test: `DevSpaceTests/Run/LogBufferTests.swift`

**Interfaces:**
- Consumes: `ANSIParser.Event`, `LogLine`, `LogStyle`.
- Produces: `LogChange.append([LogLine]) / .replaceLast(LogLine) / .dropFirst(Int) / .clear`;
  `LogBuffer(capacity: Int = 20_000)`, `lines`, `plainText`,
  `mutating apply(_ events: [ANSIParser.Event]) -> [LogChange]`,
  `mutating clear() -> [LogChange]`.
  Contrato: aplicar as mudanças devolvidas, em ordem, sobre uma cópia das
  linhas anteriores reproduz `lines` exatamente.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import DevSpace

private let plain = LogStyle()
private let red = LogStyle(foreground: .palette(1))

private func line(_ text: String) -> LogLine {
    LogLine(spans: text.isEmpty ? [] : [LogSpan(text: text, style: plain)])
}

@Test func textThenNewlineOpensAFreshLine() {
    var buffer = LogBuffer(capacity: 100)
    let changes = buffer.apply([.text("a", plain), .newline, .text("b", plain)])
    #expect(buffer.lines == [line("a"), line("b")])
    #expect(changes == [.append([line("a"), line("b")])])
}

@Test func laterTextReplacesTheOpenLine() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plain)])
    #expect(buffer.apply([.text("b", plain)]) == [.replaceLast(line("ab"))])
}

@Test func carriageReturnMakesTheNextTextOverwrite() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("10%", plain)])
    #expect(buffer.apply([.carriageReturn, .text("20%", plain)]) == [.replaceLast(line("20%"))])
    #expect(buffer.plainText == "20%")
}

@Test func crlfDoesNotEraseTheLine() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plain), .carriageReturn, .newline, .text("b", plain)])
    #expect(buffer.plainText == "a\nb")
}

@Test func eraseToEndOnlyClearsAfterACarriageReturn() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("keep", plain), .eraseToEnd])
    #expect(buffer.plainText == "keep")
    _ = buffer.apply([.carriageReturn, .eraseToEnd])
    #expect(buffer.plainText == "")
}

@Test func eraseLineClearsTheOpenLine() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("x", plain), .eraseLine, .text("y", plain)])
    #expect(buffer.plainText == "y")
}

@Test func adjacentTextWithTheSameStyleSharesASpan() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plain), .text("b", plain), .text("c", red)])
    #expect(buffer.lines == [LogLine(spans: [LogSpan(text: "ab", style: plain),
                                             LogSpan(text: "c", style: red)])])
}

@Test func newlineOnAnEmptyBufferKeepsTheBlankLine() {
    var buffer = LogBuffer(capacity: 100)
    #expect(buffer.apply([.newline]) == [.append([line(""), line("")])])
    #expect(buffer.plainText == "\n")
}

@Test func overflowDropsTheOldestLines() {
    var buffer = LogBuffer(capacity: 3)
    _ = buffer.apply([.text("1", plain), .newline, .text("2", plain), .newline])
    let changes = buffer.apply([.text("3", plain), .newline, .text("4", plain)])
    #expect(buffer.lines == [line("2"), line("3"), line("4")])
    #expect(changes == [.dropFirst(1), .replaceLast(line("3")), .append([line("4")])])
}

@Test func aFloodLargerThanTheCapacityResetsTheView() {
    var buffer = LogBuffer(capacity: 2)
    _ = buffer.apply([.text("old", plain)])
    let changes = buffer.apply([.newline, .text("a", plain), .newline, .text("b", plain),
                                .newline, .text("c", plain)])
    #expect(buffer.lines == [line("b"), line("c")])
    #expect(changes == [.clear, .append([line("b"), line("c")])])
}

@Test func clearEmptiesTheBuffer() {
    var buffer = LogBuffer(capacity: 100)
    _ = buffer.apply([.text("a", plain), .carriageReturn])
    #expect(buffer.clear() == [.clear])
    #expect(buffer.lines.isEmpty)
    _ = buffer.apply([.text("b", plain)])
    #expect(buffer.plainText == "b")
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'LogBuffer' in scope`.

- [ ] **Step 3: Write the buffer**

```swift
import Foundation

nonisolated enum LogChange: Equatable, Sendable {
    case append([LogLine])
    case replaceLast(LogLine)
    case dropFirst(Int)
    case clear
}

nonisolated struct LogBuffer: Sendable {
    let capacity: Int
    private(set) var lines: [LogLine] = []
    private var cursorAtStart = false

    init(capacity: Int = 20_000) {
        self.capacity = capacity
    }

    var plainText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    mutating func apply(_ events: [ANSIParser.Event]) -> [LogChange] {
        let initialCount = lines.count
        var changes: [LogChange] = []
        for event in events {
            switch event {
            case .text(let text, let style):
                openLineIfNeeded(&changes)
                let last = lines.count - 1
                if cursorAtStart {
                    lines[last] = LogLine()
                    cursorAtStart = false
                }
                lines[last].append(text, style: style)
                Self.record(.replaceLast(lines[last]), into: &changes)
            case .newline:
                openLineIfNeeded(&changes)
                lines.append(LogLine())
                cursorAtStart = false
                Self.record(.append([LogLine()]), into: &changes)
            case .carriageReturn:
                cursorAtStart = true
            case .eraseToEnd:
                if cursorAtStart { clearOpenLine(&changes) }
            case .eraseLine:
                clearOpenLine(&changes)
            }
        }

        let overflow = lines.count - capacity
        guard overflow > 0 else { return changes }
        lines.removeFirst(overflow)
        if overflow >= initialCount { return [.clear, .append(lines)] }
        return [.dropFirst(overflow)] + changes
    }

    mutating func clear() -> [LogChange] {
        lines = []
        cursorAtStart = false
        return [.clear]
    }

    private mutating func openLineIfNeeded(_ changes: inout [LogChange]) {
        guard lines.isEmpty else { return }
        lines.append(LogLine())
        Self.record(.append([LogLine()]), into: &changes)
    }

    private mutating func clearOpenLine(_ changes: inout [LogChange]) {
        guard let last = lines.indices.last, !lines[last].spans.isEmpty else { return }
        lines[last] = LogLine()
        Self.record(.replaceLast(LogLine()), into: &changes)
    }

    private static func record(_ change: LogChange, into changes: inout [LogChange]) {
        guard let previous = changes.last else {
            changes.append(change)
            return
        }
        switch (previous, change) {
        case (.append, .replaceLast(let line)):
            guard case .append(var lines) = changes.removeLast() else { return }
            lines[lines.count - 1] = line
            changes.append(.append(lines))
        case (.replaceLast, .replaceLast):
            changes[changes.count - 1] = change
        case (.append, .append(let more)):
            guard case .append(var lines) = changes.removeLast() else { return }
            lines.append(contentsOf: more)
            changes.append(.append(lines))
        default:
            changes.append(change)
        }
    }
}
```

- [ ] **Step 4: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 6: `LogIntake` (parser fora da main thread, entrega em lotes)

**Files:**
- Create: `DevSpace/Run/Services/LogIntake.swift`
- Test: `DevSpaceTests/Run/LogIntakeTests.swift`

**Interfaces:**
- Consumes: `ANSIParser`.
- Produces: `LogIntake(interval: Duration = .milliseconds(60), deliver: @escaping @MainActor @Sendable ([ANSIParser.Event]) -> Void)`,
  `func receive(_ data: Data)` (qualquer thread),
  `func finish(then: @escaping @MainActor @Sendable () -> Void)` — entrega tudo
  o que falta e só então chama `then`, na main.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DevSpace

private final class Received {
    var events: [ANSIParser.Event] = []
    var batches = 0
}

@Test func intakeDeliversEverythingBeforeTheCompletion() async {
    let received = Received()
    await withCheckedContinuation { continuation in
        let intake = LogIntake(interval: .zero) { received.events += $0 }
        intake.receive(Data("a\n".utf8))
        intake.receive(Data("\u{1B}[31mb".utf8))
        intake.finish { continuation.resume() }
    }
    #expect(received.events == [
        .text("a", LogStyle()), .newline,
        .text("b", LogStyle(foreground: .palette(1))),
    ])
}

@Test func intakeBatchesChunksThatArriveTogether() async {
    let received = Received()
    await withCheckedContinuation { continuation in
        let intake = LogIntake(interval: .milliseconds(200)) { _ in received.batches += 1 }
        for index in 0..<50 { intake.receive(Data("\(index)\n".utf8)) }
        intake.finish { continuation.resume() }
    }
    #expect(received.batches == 1)
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'LogIntake' in scope`.

- [ ] **Step 3: Write the intake**

```swift
import Foundation

nonisolated final class LogIntake: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = ANSIParser()
    private var pending: [ANSIParser.Event] = []
    private var flushScheduled = false
    private let interval: Duration
    private let deliver: @MainActor @Sendable ([ANSIParser.Event]) -> Void

    init(interval: Duration = .milliseconds(60),
         deliver: @escaping @MainActor @Sendable ([ANSIParser.Event]) -> Void) {
        self.interval = interval
        self.deliver = deliver
    }

    func receive(_ data: Data) {
        let schedule: Bool = lock.withLock {
            pending += parser.feed(data)
            guard !flushScheduled, !pending.isEmpty else { return false }
            flushScheduled = true
            return true
        }
        guard schedule else { return }
        let interval = self.interval
        Task { @MainActor [self] in
            try? await Task.sleep(for: interval)
            drain()
        }
    }

    func finish(then completion: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { pending += parser.finish() }
        Task { @MainActor [self] in
            drain()
            completion()
        }
    }

    @MainActor
    private func drain() {
        let events: [ANSIParser.Event] = lock.withLock {
            let taken = pending
            pending = []
            flushScheduled = false
            return taken
        }
        if !events.isEmpty { deliver(events) }
    }
}
```

- [ ] **Step 4: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 7: `ShellEnvironment` e `ShellProbe`

**Files:**
- Create: `DevSpace/Run/Services/ShellEnvironment.swift`
- Test: `DevSpaceTests/Run/ShellEnvironmentTests.swift`

**Interfaces:**
- Produces:
  - `actor ShellEnvironment`, `init(shell: String = ShellEnvironment.loginShell(), base: [String: String] = ProcessInfo.processInfo.environment, timeout: Duration = .seconds(5), probe: @escaping Probe = ShellProbe.run)`
  - `typealias Probe = @Sendable (String, [String], Duration) async -> Data?` (shell, argumentos, prazo)
  - `func resolve() async -> Resolved`; `Resolved(shell:variables:warning:)`
  - `static let marker = "__DEVSPACE_ENV__"`, `static let fallbackWarning`
  - `static func parse(_ output: Data) -> [String: String]?`, `static func fallback(from:)`,
    `static func loginShell() -> String`
  - `ShellProbe.run(shell:arguments:timeout:) async -> Data?` — mata o shell ao
    estourar o prazo e devolve `nil`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DevSpace

private func output(_ text: String) -> Data { Data(text.utf8) }

nonisolated private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@Test func parseReadsOnlyWhatFollowsTheMarker() {
    let data = output("Welcome to fish\n__DEVSPACE_ENV__\nPATH=/x:/y\u{0}HOME=/h\u{0}")
    #expect(ShellEnvironment.parse(data) == ["PATH": "/x:/y", "HOME": "/h"])
}

@Test func parseKeepsEverythingAfterTheFirstEquals() {
    let data = output("__DEVSPACE_ENV__\nDATABASE_URL=postgres://u:p@h/db?a=b\u{0}")
    #expect(ShellEnvironment.parse(data)?["DATABASE_URL"] == "postgres://u:p@h/db?a=b")
}

@Test func parseDropsShellBookkeepingVariables() {
    let data = output("__DEVSPACE_ENV__\nPATH=/x\u{0}PWD=/home\u{0}OLDPWD=/\u{0}SHLVL=2\u{0}_=/usr/bin/env\u{0}")
    #expect(ShellEnvironment.parse(data) == ["PATH": "/x"])
}

@Test func parseWithoutTheMarkerIsNil() {
    #expect(ShellEnvironment.parse(output("PATH=/x\u{0}")) == nil)
}

@Test func fallbackPrependsHomebrewPathsOnce() {
    let result = ShellEnvironment.fallback(from: ["PATH": "/usr/bin:/usr/local/bin", "PWD": "/"])
    #expect(result["PATH"] == "/opt/homebrew/bin:/usr/bin:/usr/local/bin")
    #expect(result["PWD"] == nil)
}

@Test func resolveUsesTheProbeOnceAndCaches() async {
    let calls = CallCounter()
    let environment = ShellEnvironment(shell: "/bin/zsh", base: [:]) { shell, arguments, _ in
        calls.bump()
        #expect(shell == "/bin/zsh")
        #expect(arguments == ["-l", "-i", "-c", "echo __DEVSPACE_ENV__; /usr/bin/env -0"])
        return Data("__DEVSPACE_ENV__\nPATH=/nvm/bin\u{0}".utf8)
    }
    let first = await environment.resolve()
    let second = await environment.resolve()
    #expect(first == ShellEnvironment.Resolved(shell: "/bin/zsh", variables: ["PATH": "/nvm/bin"], warning: nil))
    #expect(second == first)
    #expect(calls.count == 1)
}

@Test func aFailedProbeFallsBackWithAWarning() async {
    let environment = ShellEnvironment(shell: "/bin/zsh", base: ["PATH": "/usr/bin"]) { _, _, _ in nil }
    let resolved = await environment.resolve()
    #expect(resolved.warning == ShellEnvironment.fallbackWarning)
    #expect(resolved.variables["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin")
}

@Test func anOutputWithoutPathAlsoFallsBack() async {
    let environment = ShellEnvironment(shell: "/bin/zsh", base: [:]) { _, _, _ in
        Data("__DEVSPACE_ENV__\nHOME=/h\u{0}".utf8)
    }
    #expect(await environment.resolve().warning == ShellEnvironment.fallbackWarning)
}

@Test func theLiveProbeReadsARealShell() async throws {
    let data = try #require(await ShellProbe.run(
        shell: "/bin/sh", arguments: ["-c", "echo __DEVSPACE_ENV__; /usr/bin/env -0"],
        timeout: .seconds(10)))
    #expect(ShellEnvironment.parse(data)?["PATH"] != nil)
}

@Test func theLiveProbeGivesUpOnAHungShell() async {
    let data = await ShellProbe.run(shell: "/bin/sh", arguments: ["-c", "sleep 30"],
                                    timeout: .milliseconds(300))
    #expect(data == nil)
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'ShellEnvironment' in scope`.

- [ ] **Step 3: Write the environment and the probe**

```swift
import Darwin
import Foundation

actor ShellEnvironment {
    nonisolated struct Resolved: Equatable, Sendable {
        var shell: String
        var variables: [String: String]
        var warning: String?
    }

    typealias Probe = @Sendable (_ shell: String, _ arguments: [String], _ timeout: Duration) async -> Data?

    nonisolated static let marker = "__DEVSPACE_ENV__"
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

    nonisolated static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let path = String(cString: raw)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
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
```

- [ ] **Step 4: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 8: `PTYProcess`

**Files:**
- Create: `DevSpace/Run/Services/PTYProcess.swift`
- Test: `DevSpaceTests/Run/PTYProcessTests.swift`

**Interfaces:**
- Produces:
  - `LaunchRequest(shell:command:directory:environment:)`
  - `ProcessExit.code(Int32) / .signal(Int32)`, `init(waitStatus: Int32)`
  - `LaunchError.terminalUnavailable(Int32) / .spawnFailed(Int32)`
  - `protocol RunningProcess: AnyObject, Sendable { var pid: Int32 { get }; func terminate(grace: Duration) async }`
  - `protocol ProcessLaunching: Sendable { func launch(_:onOutput:onExit:) throws -> any RunningProcess }`
  - `PTYLauncher()` (implementação real), `PTYProcess.spawn(_:onOutput:onExit:) throws -> PTYProcess`
  - Garantias: `onExit` é chamado uma vez, depois do último `onOutput` do
    processo; `terminate` manda `SIGTERM` ao grupo, espera `grace` e manda
    `SIGKILL` ao grupo.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import Darwin
@testable import DevSpace

nonisolated private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var status: ProcessExit?
    private var exits = 0

    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    func finish(_ value: ProcessExit) { lock.withLock { status = value; exits += 1 } }
    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "") }
    }
    var exitStatus: ProcessExit? { lock.withLock { status } }
    var exitCount: Int { lock.withLock { exits } }
}

private func launch(_ command: String,
                    in directory: URL = FileManager.default.temporaryDirectory,
                    environment: [String: String] = ["PATH": "/usr/bin:/bin"],
                    shell: String = "/bin/sh") throws -> (PTYProcess, Recorder) {
    let recorder = Recorder()
    let process = try PTYProcess.spawn(
        LaunchRequest(shell: shell, command: command, directory: directory, environment: environment),
        onOutput: { recorder.append($0) },
        onExit: { recorder.finish($0) })
    return (process, recorder)
}

private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Test func outputArrivesThroughATerminal() async throws {
    let (_, recorder) = try launch("test -t 1 && echo IS_TTY; printf 'a\\nb\\n'")
    await waitUntil { recorder.exitStatus != nil }
    #expect(recorder.exitStatus == .code(0))
    #expect(recorder.text == "IS_TTY\na\nb\n")
}

@Test func anInstantExitStillDeliversEverything() async throws {
    let (_, recorder) = try launch("seq 1 2000")
    await waitUntil { recorder.exitStatus != nil }
    let lines = recorder.text.split(separator: "\n")
    #expect(lines.count == 2000)
    #expect(lines.last == "2000")
    #expect(recorder.exitCount == 1)
}

@Test func theExitCodeIsReported() async throws {
    let (_, recorder) = try launch("exit 3")
    await waitUntil { recorder.exitStatus != nil }
    #expect(recorder.exitStatus == .code(3))
}

@Test func aSignalDeathIsReported() async throws {
    let (_, recorder) = try launch("kill -9 $$")
    await waitUntil { recorder.exitStatus != nil }
    #expect(recorder.exitStatus == .signal(SIGKILL))
}

@Test func theWorkingDirectoryAndEnvironmentAreApplied() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
        .appending(path: "pasta com espaço ç")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let (_, recorder) = try launch("pwd; echo \"$GREETING\"", in: directory,
                                   environment: ["PATH": "/usr/bin:/bin", "GREETING": "olá=mundo"])
    await waitUntil { recorder.exitStatus != nil }
    let lines = recorder.text.split(separator: "\n").map(String.init)
    #expect(lines.first?.hasSuffix("/pasta com espaço ç") == true)
    #expect(lines.last == "olá=mundo")
}

@Test func aMissingShellFailsToSpawn() {
    #expect(throws: LaunchError.self) {
        _ = try launch("true", shell: "/nonexistent/shell")
    }
}

@Test func terminateTakesDownTheWholeGroup() async throws {
    let (process, recorder) = try launch("sleep 60 & echo $!; wait")
    await waitUntil { recorder.text.contains("\n") }
    let child = try #require(Int32(recorder.text.trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(kill(child, 0) == 0)

    await process.terminate(grace: .seconds(5))
    await waitUntil { kill(child, 0) != 0 }

    #expect(kill(child, 0) != 0)
    #expect(recorder.exitStatus == .signal(SIGTERM))
}

@Test func aProcessIgnoringTermIsKilled() async throws {
    let (process, recorder) = try launch("trap '' TERM; echo ready; while :; do sleep 1; done")
    await waitUntil { recorder.text.contains("ready") }

    await process.terminate(grace: .milliseconds(300))
    await waitUntil { recorder.exitStatus != nil }

    #expect(recorder.exitStatus == .signal(SIGKILL))
}

@Test func terminateAfterExitDoesNothing() async throws {
    let (process, recorder) = try launch("true")
    await waitUntil { recorder.exitStatus != nil }
    await process.terminate(grace: .seconds(1))
    #expect(recorder.exitCount == 1)
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'PTYProcess' in scope`.

- [ ] **Step 3: Write the process layer**

```swift
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

    let pid: Int32
    private let master: Int32
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

    private init(pid: Int32, master: Int32,
                 onOutput: @escaping @Sendable (Data) -> Void,
                 onExit: @escaping @Sendable (ProcessExit) -> Void) {
        self.pid = pid
        self.master = master
        self.queue = DispatchQueue(label: "DevSpace.PTYProcess.\(pid)", qos: .userInitiated)
        self.onOutput = onOutput
        self.onExit = onExit
    }

    var hasExited: Bool { lock.withLock { exited } }

    static func spawn(_ request: LaunchRequest,
                      onOutput: @escaping @Sendable (Data) -> Void,
                      onExit: @escaping @Sendable (ProcessExit) -> Void) throws -> PTYProcess {
        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            throw LaunchError.terminalUnavailable(errno)
        }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(slave, F_SETFD, FD_CLOEXEC)

        var attributes: posix_spawnattr_t? = nil
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

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, slave, 1)
        posix_spawn_file_actions_adddup2(&actions, slave, 2)
        posix_spawn_file_actions_addchdir(&actions, request.directory.path)

        let arguments = [request.shell, "-c", request.command]
        let environment = request.environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let result = withCStrings(arguments) { argv in
            withCStrings(environment) { envp in
                posix_spawn(&pid, request.shell, &actions, &attributes, argv, envp)
            }
        }
        close(slave)
        guard result == 0 else {
            close(master)
            throw LaunchError.spawnFailed(result)
        }

        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        let process = PTYProcess(pid: pid, master: master, onOutput: onOutput, onExit: onExit)
        process.startMonitoring()
        return process
    }

    func terminate(grace: Duration) async {
        guard !hasExited else { return }
        kill(-pid, SIGTERM)
        if await waitForExit(within: grace) { return }
        kill(-pid, SIGKILL)
        _ = await waitForExit(within: .seconds(2))
    }

    private func waitForExit(within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            if hasExited { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return hasExited
    }

    private func startMonitoring() {
        let read = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        read.setEventHandler { self.drain() }
        read.setCancelHandler { close(self.master) }
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
            let count = buffer.withUnsafeMutableBytes { Darwin.read(master, $0.baseAddress, $0.count) }
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
        onExit(result == pid ? ProcessExit(waitStatus: status) : .code(-1))
        lock.withLock { exited = true }
    }

    private static func withCStrings<R>(_ strings: [String],
                                        _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        let pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
    }
}
```

- [ ] **Step 4: Run the suite**

Expected: TEST SUCCEEDED. If `sigfillset`/`sigdelset` don't import as
functions, replace them with `var defaults = sigset_t(UInt32.max)` and clear
the bits with `defaults &= ~(1 << (SIGKILL - 1))` / `~(1 << (SIGSTOP - 1))`,
and `sigemptyset` with `sigset_t(0)`.

---

### Task 9: `RunInstance`, `RunManager` e `RunStatus`

**Files:**
- Create: `DevSpace/Run/RunInstance.swift`
- Create: `DevSpace/Run/RunManager.swift`
- Create: `DevSpace/Run/Models/RunStatus.swift`
- Create: `DevSpaceTests/Support/FakeLauncher.swift`
- Test: `DevSpaceTests/Run/RunManagerTests.swift`
- Test: `DevSpaceTests/Run/RunStatusTests.swift`

**Interfaces:**
- Consumes: `ProcessLaunching`, `RunningProcess`, `LaunchRequest`,
  `ProcessExit`, `LaunchError`, `ShellEnvironment`, `LogIntake`, `LogBuffer`,
  `RunConfiguration`, `CommandSpec.resolvedDirectory(in:)`.
- Produces:
  - `RunInstance.State`: `.starting`, `.running(pid: Int32)`, `.stopping`,
    `.stopped`, `.exited(ProcessExit)`, `.failed(String)`
  - `RunInstance`: `configurationID`, `state`, `startedAt`, `isActive`,
    `log: LogBuffer`, `observeLog(_:) -> UUID`, `stopObserving(_:)`, `clearLog()`
  - `RunManager(launcher:environment:stopGrace:logInterval:)`,
    `instance(for:) -> RunInstance?`, `start(_:in:) async`, `stop(_:) async`,
    `stopAll(grace:) async`, `forget(_:)`, `hasActiveProcesses`
  - `RunIndicator.idle / .busy / .running / .failed`,
    `RunStatus.label(for:startedAt:now:) -> String`, `RunStatus.indicator(for:)`

- [ ] **Step 1: Write the fake launcher**

```swift
import Foundation
import Darwin
@testable import DevSpace

nonisolated final class FakeProcess: RunningProcess, @unchecked Sendable {
    let pid: Int32
    private let onOutput: @Sendable (Data) -> Void
    private let onExit: @Sendable (ProcessExit) -> Void
    private let lock = NSLock()
    private var terminateCalls = 0

    init(pid: Int32, onOutput: @escaping @Sendable (Data) -> Void,
         onExit: @escaping @Sendable (ProcessExit) -> Void) {
        self.pid = pid
        self.onOutput = onOutput
        self.onExit = onExit
    }

    var terminations: Int { lock.withLock { terminateCalls } }

    func emit(_ text: String) { onOutput(Data(text.utf8)) }
    func exit(_ status: ProcessExit) { onExit(status) }

    func terminate(grace: Duration) async {
        lock.withLock { terminateCalls += 1 }
        onExit(.signal(SIGTERM))
    }
}

nonisolated final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var launched: [(LaunchRequest, FakeProcess)] = []
    private var nextFailure: LaunchError?

    func fail(with error: LaunchError) { lock.withLock { nextFailure = error } }

    var requests: [LaunchRequest] { lock.withLock { launched.map(\.0) } }
    var processes: [FakeProcess] { lock.withLock { launched.map(\.1) } }

    func launch(_ request: LaunchRequest,
                onOutput: @escaping @Sendable (Data) -> Void,
                onExit: @escaping @Sendable (ProcessExit) -> Void) throws -> any RunningProcess {
        try lock.withLock {
            if let nextFailure {
                self.nextFailure = nil
                throw nextFailure
            }
            let process = FakeProcess(pid: Int32(100 + launched.count),
                                      onOutput: onOutput, onExit: onExit)
            launched.append((request, process))
            return process
        }
    }
}
```

- [ ] **Step 2: Write the failing manager tests**

```swift
import Testing
import Foundation
import Darwin
@testable import DevSpace

private let project = FileManager.default.temporaryDirectory

nonisolated private func shellOutput() -> Data { Data("__DEVSPACE_ENV__\nPATH=/bin\u{0}".utf8) }

private func makeManager(_ launcher: FakeLauncher,
                         probe: @escaping ShellEnvironment.Probe = { _, _, _ in shellOutput() }) -> RunManager {
    RunManager(launcher: launcher,
               environment: ShellEnvironment(shell: "/bin/zsh", base: ["PATH": "/usr/bin"], probe: probe),
               stopGrace: .seconds(1), logInterval: .zero)
}

private func command(_ name: String = "API", _ command: String = "npm run dev",
                     directory: String = "", environment: [EnvVar] = []) -> RunConfiguration {
    RunConfiguration(name: name, kind: .command(CommandSpec(
        command: command, workingDirectory: directory, environment: environment)))
}

private func eventually(_ condition: () -> Bool) async {
    for _ in 0..<500 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Test func startLaunchesTheCommandThroughTheShell() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command(environment: [EnvVar(key: "PORT", value: "3000")])

    await manager.start(api, in: project)

    let request = try #require(launcher.requests.first)
    #expect(request.shell == "/bin/zsh")
    #expect(request.command == "npm run dev")
    #expect(request.directory == project)
    #expect(request.environment["PATH"] == "/bin")
    #expect(request.environment["TERM"] == "xterm-256color")
    #expect(request.environment["COLORTERM"] == "truecolor")
    #expect(request.environment["PORT"] == "3000")
    #expect(manager.instance(for: api.id)?.state == .running(pid: 100))
    #expect(manager.hasActiveProcesses)
}

@Test func configurationVariablesWinAndBlankKeysAreSkipped() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    await manager.start(command(environment: [EnvVar(key: "TERM", value: "dumb"),
                                              EnvVar(key: " ", value: "x"),
                                              EnvVar(key: "A=B", value: "y")]), in: project)

    let environment = try #require(launcher.requests.first?.environment)
    #expect(environment["TERM"] == "dumb")
    #expect(environment[" "] == nil)
    #expect(environment[""] == nil)
    #expect(environment["A=B"] == nil)
}

@Test func outputReachesTheInstanceLog() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))

    launcher.processes[0].emit("hello \u{1B}[32mworld\u{1B}[0m\n")
    await eventually { instance.log.plainText == "hello world\n" }

    #expect(instance.log.plainText == "hello world\n")
}

@Test func anExitOnItsOwnIsRecorded() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))

    launcher.processes[0].exit(.code(1))
    await eventually { instance.state == .exited(.code(1)) }

    #expect(instance.state == .exited(.code(1)))
    #expect(!manager.hasActiveProcesses)
}

@Test func stopMarksTheInstanceStopped() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))

    await manager.stop(api.id)
    await eventually { instance.state == .stopped }

    #expect(instance.state == .stopped)
    #expect(launcher.processes[0].terminations == 1)
    #expect(!manager.hasActiveProcesses)
}

@Test func startingARunningConfigurationRestartsIt() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))
    let first = launcher.processes[0]
    first.emit("old\n")
    await eventually { instance.log.plainText.contains("old") }

    await manager.start(api, in: project)

    #expect(first.terminations == 1)
    #expect(launcher.processes.count == 2)
    #expect(instance.state == .running(pid: 101))
    #expect(!instance.log.plainText.contains("old"))

    first.emit("late\n")
    first.exit(.code(0))
    launcher.processes[1].emit("fresh\n")
    await eventually { instance.log.plainText.contains("fresh") }

    #expect(!instance.log.plainText.contains("late"))
    #expect(instance.state == .running(pid: 101))
    #expect(manager.instance(for: api.id) === instance)
}

@Test func aMissingDirectoryFailsWithoutLaunching() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command(directory: "missing-\(UUID().uuidString)")

    await manager.start(api, in: project)

    let instance = try #require(manager.instance(for: api.id))
    guard case .failed(let message) = instance.state else {
        Issue.record("expected a failure, got \(instance.state)")
        return
    }
    #expect(message.contains("não existe"))
    #expect(instance.log.plainText.contains(message))
    #expect(launcher.requests.isEmpty)
}

@Test func aLaunchErrorBecomesAFailure() async throws {
    let launcher = FakeLauncher()
    launcher.fail(with: .spawnFailed(ENOENT))
    let manager = makeManager(launcher)
    let api = command()

    await manager.start(api, in: project)

    guard case .failed? = manager.instance(for: api.id)?.state else {
        Issue.record("expected a failure")
        return
    }
    #expect(!manager.hasActiveProcesses)
}

@Test func theShellFallbackWarningOpensTheLog() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher) { _, _, _ in nil }
    let api = command()

    await manager.start(api, in: project)

    let instance = try #require(manager.instance(for: api.id))
    #expect(instance.log.lines.first?.text == ShellEnvironment.fallbackWarning)
}

@Test func stoppingWhileTheEnvironmentResolvesCancelsTheStart() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher) { _, _, _ in
        try? await Task.sleep(for: .milliseconds(300))
        return shellOutput()
    }
    let api = command()

    let start = Task { await manager.start(api, in: project) }
    await eventually { manager.instance(for: api.id)?.state == .starting }
    await manager.stop(api.id)
    await start.value

    #expect(manager.instance(for: api.id)?.state == .stopped)
    #expect(launcher.requests.isEmpty)
}

@Test func stopAllTerminatesEverything() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    await manager.start(command("API"), in: project)
    await manager.start(command("Web"), in: project)

    await manager.stopAll(grace: .seconds(1))
    await eventually { !manager.hasActiveProcesses }

    #expect(launcher.processes.map(\.terminations) == [1, 1])
    #expect(!manager.hasActiveProcesses)
}

@Test func forgetDropsAnIdleInstanceOnly() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)

    manager.forget(api.id)
    #expect(manager.instance(for: api.id) != nil)

    await manager.stop(api.id)
    await eventually { manager.instance(for: api.id)?.state == .stopped }
    manager.forget(api.id)
    #expect(manager.instance(for: api.id) == nil)
}
```

- [ ] **Step 3: Write the failing status tests**

```swift
import Testing
import Foundation
import Darwin
@testable import DevSpace

private let start = Date(timeIntervalSince1970: 1_000_000)

private func label(_ state: RunInstance.State?, after seconds: TimeInterval = 0) -> String {
    RunStatus.label(for: state, startedAt: start, now: start.addingTimeInterval(seconds))
}

@Test func labelsDescribeEachState() {
    #expect(label(nil) == "Não iniciada")
    #expect(label(.starting) == "Iniciando…")
    #expect(label(.running(pid: 1), after: 30) == "Rodando · agora")
    #expect(label(.running(pid: 1), after: 12 * 60) == "Rodando · 12 min")
    #expect(label(.running(pid: 1), after: 3_700) == "Rodando · 1 h 1 min")
    #expect(label(.running(pid: 1), after: 7_200) == "Rodando · 2 h")
    #expect(label(.stopping) == "Parando…")
    #expect(label(.stopped) == "Parado")
    #expect(label(.exited(.code(0))) == "Encerrado")
    #expect(label(.exited(.code(2))) == "Saiu com código 2")
    #expect(label(.exited(.signal(9))) == "Encerrado pelo sinal 9")
    #expect(label(.failed("A pasta /x não existe")) == "Falhou: A pasta /x não existe")
}

@Test func indicatorsFollowTheState() {
    #expect(RunStatus.indicator(for: nil) == .idle)
    #expect(RunStatus.indicator(for: .starting) == .busy)
    #expect(RunStatus.indicator(for: .running(pid: 1)) == .running)
    #expect(RunStatus.indicator(for: .stopping) == .busy)
    #expect(RunStatus.indicator(for: .stopped) == .idle)
    #expect(RunStatus.indicator(for: .exited(.code(0))) == .idle)
    #expect(RunStatus.indicator(for: .exited(.code(1))) == .failed)
    #expect(RunStatus.indicator(for: .exited(.signal(SIGSEGV))) == .failed)
    #expect(RunStatus.indicator(for: .failed("x")) == .failed)
}
```

- [ ] **Step 4: Run the suite to verify it fails**

Expected: build error `cannot find 'RunManager' in scope`.

- [ ] **Step 5: Write `RunInstance`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class RunInstance {
    nonisolated enum State: Equatable, Sendable {
        case starting
        case running(pid: Int32)
        case stopping
        case stopped
        case exited(ProcessExit)
        case failed(String)
    }

    let configurationID: UUID
    private(set) var state: State = .starting
    private(set) var startedAt = Date()

    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private(set) var log: LogBuffer
    @ObservationIgnored private var observers: [UUID: ([LogChange]) -> Void] = [:]

    init(configurationID: UUID, logCapacity: Int = 20_000) {
        self.configurationID = configurationID
        self.log = LogBuffer(capacity: logCapacity)
    }

    var isActive: Bool {
        switch state {
        case .starting, .running, .stopping: true
        case .stopped, .exited, .failed: false
        }
    }

    func begin() -> Int {
        generation += 1
        state = .starting
        startedAt = Date()
        publish(log.clear())
        return generation
    }

    func markRunning(pid: Int32) { state = .running(pid: pid) }

    func markStopping() { state = .stopping }

    func markStopped() {
        generation += 1
        state = .stopped
    }

    func fail(_ message: String) {
        appendNotice(message)
        state = .failed(message)
    }

    func finish(_ status: ProcessExit, generation: Int) {
        guard generation == self.generation else { return }
        state = state == .stopping ? .stopped : .exited(status)
    }

    func receive(_ events: [ANSIParser.Event], generation: Int) {
        guard generation == self.generation else { return }
        publish(log.apply(events))
    }

    func appendNotice(_ text: String) {
        var events: [ANSIParser.Event] = []
        if let last = log.lines.last, !last.spans.isEmpty { events.append(.newline) }
        events += [.text(text, .notice), .newline]
        publish(log.apply(events))
    }

    func clearLog() { publish(log.clear()) }

    func observeLog(_ handler: @escaping ([LogChange]) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    func stopObserving(_ token: UUID) { observers[token] = nil }

    private func publish(_ changes: [LogChange]) {
        guard !changes.isEmpty else { return }
        for observer in observers.values { observer(changes) }
    }
}
```

- [ ] **Step 6: Write `RunManager`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class RunManager {
    private(set) var instances: [UUID: RunInstance] = [:]

    @ObservationIgnored private var processes: [UUID: any RunningProcess] = [:]
    @ObservationIgnored private let launcher: any ProcessLaunching
    @ObservationIgnored private let environment: ShellEnvironment
    @ObservationIgnored private let stopGrace: Duration
    @ObservationIgnored private let logInterval: Duration

    init(launcher: any ProcessLaunching = PTYLauncher(),
         environment: ShellEnvironment = ShellEnvironment(),
         stopGrace: Duration = .seconds(5),
         logInterval: Duration = .milliseconds(60)) {
        self.launcher = launcher
        self.environment = environment
        self.stopGrace = stopGrace
        self.logInterval = logInterval
    }

    var hasActiveProcesses: Bool { !processes.isEmpty }

    func instance(for id: UUID) -> RunInstance? { instances[id] }

    func start(_ configuration: RunConfiguration, in root: URL) async {
        guard case .command(let spec) = configuration.kind else { return }
        let id = configuration.id
        let instance = instances[id] ?? RunInstance(configurationID: id)
        instances[id] = instance
        if instance.isActive { await stop(id) }
        let generation = instance.begin()
        processes[id] = nil

        let shell = await environment.resolve()
        guard instance.generation == generation else { return }
        if let warning = shell.warning { instance.appendNotice(warning) }

        let directory = spec.resolvedDirectory(in: root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            instance.fail("A pasta \(directory.path) não existe")
            return
        }

        let request = LaunchRequest(
            shell: shell.shell, command: spec.command, directory: directory,
            environment: Self.environment(base: shell.variables, overrides: spec.environment))
        let intake = LogIntake(interval: logInterval) { [weak instance] events in
            instance?.receive(events, generation: generation)
        }
        do {
            let process = try launcher.launch(
                request,
                onOutput: { intake.receive($0) },
                onExit: { [weak self] status in
                    intake.finish { [weak self] in self?.processExited(id, status: status, generation: generation) }
                })
            processes[id] = process
            instance.markRunning(pid: process.pid)
        } catch {
            instance.fail(Self.describe(error))
        }
    }

    func stop(_ id: UUID) async {
        guard let instance = instances[id], instance.isActive else { return }
        guard let process = processes[id] else {
            instance.markStopped()
            return
        }
        instance.markStopping()
        await process.terminate(grace: stopGrace)
    }

    func stopAll(grace: Duration) async {
        for instance in instances.values where instance.isActive && processes[instance.configurationID] == nil {
            instance.markStopped()
        }
        let running = processes
        for id in running.keys { instances[id]?.markStopping() }
        await withTaskGroup(of: Void.self) { group in
            for process in running.values {
                group.addTask { await process.terminate(grace: grace) }
            }
        }
    }

    func forget(_ id: UUID) {
        guard let instance = instances[id], !instance.isActive else { return }
        instances[id] = nil
    }

    private func processExited(_ id: UUID, status: ProcessExit, generation: Int) {
        guard let instance = instances[id], instance.generation == generation else { return }
        instance.finish(status, generation: generation)
        processes[id] = nil
    }

    nonisolated static func environment(base: [String: String], overrides: [EnvVar]) -> [String: String] {
        var result = base
        result["TERM"] = "xterm-256color"
        result["COLORTERM"] = "truecolor"
        for variable in overrides {
            let key = variable.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.contains("=") else { continue }
            result[key] = variable.value
        }
        return result
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch error as? LaunchError {
        case .terminalUnavailable?:
            return "Não consegui abrir um terminal para o processo"
        case .spawnFailed(let code)?:
            return "Não consegui iniciar o processo: \(String(cString: strerror(code)))"
        case nil:
            return "Não consegui iniciar o processo: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 7: Write `RunStatus`**

```swift
import Foundation

nonisolated enum RunIndicator: Equatable, Sendable {
    case idle
    case busy
    case running
    case failed
}

nonisolated enum RunStatus {
    static func label(for state: RunInstance.State?, startedAt: Date, now: Date) -> String {
        switch state {
        case nil: "Não iniciada"
        case .starting?: "Iniciando…"
        case .running?: "Rodando · \(elapsed(from: startedAt, to: now))"
        case .stopping?: "Parando…"
        case .stopped?: "Parado"
        case .exited(.code(0))?: "Encerrado"
        case .exited(.code(let code))?: "Saiu com código \(code)"
        case .exited(.signal(let signal))?: "Encerrado pelo sinal \(signal)"
        case .failed(let message)?: "Falhou: \(message)"
        }
    }

    static func indicator(for state: RunInstance.State?) -> RunIndicator {
        switch state {
        case nil, .stopped?, .exited(.code(0))?: .idle
        case .starting?, .stopping?: .busy
        case .running?: .running
        case .exited?, .failed?: .failed
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(start)) / 60
        if minutes < 1 { return "agora" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
```

- [ ] **Step 8: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 10: `LogPalette`, `LogRenderer` e `LogDocument`

**Files:**
- Create: `DevSpace/Run/Views/LogRenderer.swift`
- Test: `DevSpaceTests/Run/LogDocumentTests.swift`

**Interfaces:**
- Consumes: `LogLine`, `LogStyle`, `LogColor`, `LogChange`, `LogBuffer`.
- Produces: `LogPalette.rgb(forIndex: UInt8) -> LogPalette.RGB`;
  `LogRenderer()`, `render(_ line: LogLine) -> NSAttributedString`;
  `LogDocument(storage: NSMutableAttributedString, renderer: LogRenderer = LogRenderer())`,
  `reload(_ lines: [LogLine])`, `apply(_ changes: [LogChange])`.
  Contrato: depois de qualquer sequência, `storage.string == buffer.plainText`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import AppKit
@testable import DevSpace

private let plain = LogStyle()

private func line(_ text: String) -> LogLine {
    LogLine(spans: text.isEmpty ? [] : [LogSpan(text: text, style: plain)])
}

@Test func paletteCoversTheCubeAndTheGrayRamp() {
    #expect(LogPalette.rgb(forIndex: 16) == LogPalette.RGB(red: 0, green: 0, blue: 0))
    #expect(LogPalette.rgb(forIndex: 21) == LogPalette.RGB(red: 0, green: 0, blue: 255))
    #expect(LogPalette.rgb(forIndex: 196) == LogPalette.RGB(red: 255, green: 0, blue: 0))
    #expect(LogPalette.rgb(forIndex: 231) == LogPalette.RGB(red: 255, green: 255, blue: 255))
    #expect(LogPalette.rgb(forIndex: 232) == LogPalette.RGB(red: 8, green: 8, blue: 8))
    #expect(LogPalette.rgb(forIndex: 255) == LogPalette.RGB(red: 238, green: 238, blue: 238))
}

@Test func documentMirrorsTheBufferThroughEveryChange() {
    var buffer = LogBuffer(capacity: 3)
    let storage = NSMutableAttributedString()
    let document = LogDocument(storage: storage)
    let batches: [[ANSIParser.Event]] = [
        [.text("a", plain), .newline, .text("b", plain)],
        [.carriageReturn, .text("B", plain)],
        [.newline, .text("c", plain), .newline, .text("d", plain)],
        [.newline, .newline, .newline, .newline, .text("flood", plain)],
        [.eraseLine],
    ]
    for batch in batches {
        document.apply(buffer.apply(batch))
        #expect(storage.string == buffer.plainText)
    }
    document.apply(buffer.clear())
    #expect(storage.string == "")
}

@Test func reloadRendersEveryLine() {
    let storage = NSMutableAttributedString(string: "stale")
    LogDocument(storage: storage).reload([line("a"), line(""), line("b")])
    #expect(storage.string == "a\n\nb")
}

@Test func stylesBecomeAttributes() {
    let style = LogStyle(foreground: .rgb(255, 0, 0), underline: true)
    let rendered = LogRenderer().render(LogLine(spans: [LogSpan(text: "x", style: style)]))
    let attributes = rendered.attributes(at: 0, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color?.usingColorSpace(.sRGB)?.redComponent == 1)
    #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'LogDocument' in scope`.

- [ ] **Step 3: Write the renderer and the document**

```swift
import AppKit

nonisolated enum LogPalette {
    struct RGB: Equatable, Sendable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    static let light: [UInt32] = [
        0x000000, 0xCD3131, 0x00BC00, 0x949800, 0x0451A5, 0xBC05BC, 0x0598BC, 0x555555,
        0x666666, 0xCD3131, 0x14CE14, 0xB5BA00, 0x0451A5, 0xBC05BC, 0x0598BC, 0xA5A5A5,
    ]

    static let dark: [UInt32] = [
        0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
        0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xE5E5E5,
    ]

    static func rgb(forIndex index: UInt8) -> RGB {
        switch index {
        case 0..<16:
            return rgb(hex: light[Int(index)])
        case 16...231:
            let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
            let offset = Int(index) - 16
            return RGB(red: levels[offset / 36], green: levels[(offset / 6) % 6], blue: levels[offset % 6])
        default:
            let value = UInt8(8 + (Int(index) - 232) * 10)
            return RGB(red: value, green: value, blue: value)
        }
    }

    static func rgb(hex: UInt32) -> RGB {
        RGB(red: UInt8((hex >> 16) & 0xFF), green: UInt8((hex >> 8) & 0xFF), blue: UInt8(hex & 0xFF))
    }

    static func color(_ rgb: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}

struct LogRenderer {
    static let fontSize: CGFloat = 11

    private static let standard: [NSColor] = (0..<16).map { index in
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return LogPalette.color(LogPalette.rgb(hex: dark ? LogPalette.dark[index] : LogPalette.light[index]))
        }
    }

    let regular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

    var separator: NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: regular])
    }

    func render(_ line: LogLine) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in line.spans {
            result.append(NSAttributedString(string: span.text, attributes: attributes(for: span.style)))
        }
        return result
    }

    func attributes(for style: LogStyle) -> [NSAttributedString.Key: Any] {
        var font = style.bold ? bold : regular
        if style.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        var foreground = style.foreground.map { Self.color($0) } ?? .textColor
        var background = style.background.map { Self.color($0) }
        if style.inverse {
            let swapped = foreground
            foreground = background ?? .textBackgroundColor
            background = swapped
        }
        if style.dim { foreground = foreground.withAlphaComponent(0.6) }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        if let background { attributes[.backgroundColor] = background }
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    static func color(_ color: LogColor) -> NSColor {
        switch color {
        case .rgb(let red, let green, let blue):
            return LogPalette.color(LogPalette.RGB(red: red, green: green, blue: blue))
        case .palette(let index):
            return index < 16 ? standard[Int(index)] : LogPalette.color(LogPalette.rgb(forIndex: index))
        }
    }
}

final class LogDocument {
    private let storage: NSMutableAttributedString
    private let renderer: LogRenderer
    private var lengths: [Int] = []

    init(storage: NSMutableAttributedString, renderer: LogRenderer = LogRenderer()) {
        self.storage = storage
        self.renderer = renderer
    }

    func reload(_ lines: [LogLine]) {
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString())
        lengths = []
        append(lines)
        storage.endEditing()
    }

    func apply(_ changes: [LogChange]) {
        storage.beginEditing()
        for change in changes {
            switch change {
            case .append(let lines): append(lines)
            case .replaceLast(let line): replaceLast(line)
            case .dropFirst(let count): dropFirst(count)
            case .clear:
                storage.setAttributedString(NSAttributedString())
                lengths = []
            }
        }
        storage.endEditing()
    }

    private func append(_ lines: [LogLine]) {
        let chunk = NSMutableAttributedString()
        for line in lines {
            if !lengths.isEmpty { chunk.append(renderer.separator) }
            let rendered = renderer.render(line)
            chunk.append(rendered)
            lengths.append(rendered.length)
        }
        storage.append(chunk)
    }

    private func replaceLast(_ line: LogLine) {
        guard let last = lengths.last else {
            append([line])
            return
        }
        let rendered = renderer.render(line)
        storage.replaceCharacters(in: NSRange(location: storage.length - last, length: last), with: rendered)
        lengths[lengths.count - 1] = rendered.length
    }

    private func dropFirst(_ count: Int) {
        let count = min(count, lengths.count)
        guard count > 0 else { return }
        let separators = count < lengths.count ? count : count - 1
        let removed = lengths.prefix(count).reduce(0, +) + separators
        storage.deleteCharacters(in: NSRange(location: 0, length: removed))
        lengths.removeFirst(count)
    }
}
```

- [ ] **Step 4: Run the suite**

Expected: TEST SUCCEEDED.

---

### Task 11: Interface — painel, toolbar, sheet, `AppDelegate`

**Files:**
- Create: `DevSpace/App/InspectorPane.swift`
- Create: `DevSpace/App/AppDelegate.swift`
- Modify: `DevSpace/App/DevSpaceApp.swift`
- Modify: `DevSpace/App/ContentView.swift` (só o `#Preview`)
- Modify: `DevSpace/Chat/Views/ChatView.swift` (`showChanges` → `pane`, inspector, toolbar)
- Create: `DevSpace/Run/Views/LogView.swift`
- Create: `DevSpace/Run/Views/RunConfigurationRow.swift`
- Create: `DevSpace/Run/Views/RunConfigurationSheet.swift`
- Create: `DevSpace/Run/Views/RunPanel.swift`
- Test: `DevSpaceTests/App/InspectorPaneTests.swift`

**Interfaces:**
- Consumes: tudo das tasks 1–10.
- Produces: `InspectorPane` (`.closed`, `.changes`, `.run`,
  `storageKey = "DevSpace.inspector"`, `migrateLegacy(in:)`);
  `AppDelegate.runs`, `AppDelegate.runConfigurations`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import DevSpace

private func withDefaults(_ body: (UserDefaults) -> Void) {
    let suite = "DevSpaceTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    body(defaults)
}

@Test func aLegacyOpenInspectorBecomesTheChangesPane() {
    withDefaults { defaults in
        defaults.set(true, forKey: "DevSpace.gitInspector")
        InspectorPane.migrateLegacy(in: defaults)
        #expect(defaults.string(forKey: InspectorPane.storageKey) == "changes")
        #expect(defaults.object(forKey: "DevSpace.gitInspector") == nil)
    }
}

@Test func aLegacyClosedInspectorLeavesThePaneClosed() {
    withDefaults { defaults in
        defaults.set(false, forKey: "DevSpace.gitInspector")
        InspectorPane.migrateLegacy(in: defaults)
        #expect(defaults.string(forKey: InspectorPane.storageKey) == nil)
        #expect(defaults.object(forKey: "DevSpace.gitInspector") == nil)
    }
}

@Test func anExistingPaneIsNotOverwritten() {
    withDefaults { defaults in
        defaults.set("run", forKey: InspectorPane.storageKey)
        defaults.set(true, forKey: "DevSpace.gitInspector")
        InspectorPane.migrateLegacy(in: defaults)
        #expect(defaults.string(forKey: InspectorPane.storageKey) == "run")
    }
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Expected: build error `cannot find 'InspectorPane' in scope`.

- [ ] **Step 3: Write `InspectorPane` and `AppDelegate`**

`DevSpace/App/InspectorPane.swift`:

```swift
import Foundation

enum InspectorPane: String {
    case closed = ""
    case changes
    case run

    static let storageKey = "DevSpace.inspector"
    private static let legacyKey = "DevSpace.gitInspector"

    static func migrateLegacy(in defaults: UserDefaults) {
        guard defaults.object(forKey: legacyKey) != nil else { return }
        if defaults.bool(forKey: legacyKey), defaults.string(forKey: storageKey) == nil {
            defaults.set(InspectorPane.changes.rawValue, forKey: storageKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }
}
```

`DevSpace/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let runs = RunManager()
    let runConfigurations = RunConfigurationsModel(store: .live)

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard runs.hasActiveProcesses else { return .terminateNow }
        Task {
            await runs.stopAll(grace: .seconds(2))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

- [ ] **Step 4: Wire the app**

`DevSpace/App/DevSpaceApp.swift`:

```swift
import SwiftUI

@main
struct DevSpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        InspectorPane.migrateLegacy(in: .standard)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.runs)
                .environment(appDelegate.runConfigurations)
        }

        .commands { HarnessCommands() }

        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}
```

In `DevSpace/App/ContentView.swift`, the preview becomes:

```swift
#Preview {
    ContentView()
        .environment(RunManager())
        .environment(RunConfigurationsModel(store: .live))
}
```

- [ ] **Step 5: Write `LogView`**

```swift
import AppKit
import SwiftUI

struct LogView: NSViewRepresentable {
    let instance: RunInstance
    let followRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = true
            text.drawsBackground = false
            text.usesFindBar = true
            text.isIncrementalSearchingEnabled = true
            text.textContainerInset = NSSize(width: 6, height: 6)
            text.font = NSFont.monospacedSystemFont(ofSize: LogRenderer.fontSize, weight: .regular)
            text.setAccessibilityLabel("Log")
            context.coordinator.textView = text
        }
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.show(instance)
        context.coordinator.follow(followRequest)
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        weak var textView: NSTextView?
        private var document: LogDocument?
        private weak var instance: RunInstance?
        private var token: UUID?
        private var lastFollowRequest = 0

        func show(_ instance: RunInstance) {
            guard instance !== self.instance, let textView, let storage = textView.textStorage else { return }
            detach()
            self.instance = instance
            let document = LogDocument(storage: storage)
            document.reload(instance.log.lines)
            self.document = document
            token = instance.observeLog { [weak self] changes in self?.apply(changes) }
            scrollToEnd()
        }

        func follow(_ request: Int) {
            guard request != lastFollowRequest else { return }
            lastFollowRequest = request
            scrollToEnd()
        }

        func detach() {
            if let token { instance?.stopObserving(token) }
            token = nil
            instance = nil
            document = nil
        }

        private func apply(_ changes: [LogChange]) {
            let following = isAtEnd
            document?.apply(changes)
            if following { scrollToEnd() }
        }

        private var isAtEnd: Bool {
            guard let textView, let clip = textView.enclosingScrollView?.contentView else { return true }
            return clip.bounds.maxY >= textView.frame.height - 24
        }

        private func scrollToEnd() {
            textView?.scrollToEndOfDocument(nil)
        }
    }
}
```

- [ ] **Step 6: Write `RunConfigurationRow`**

```swift
import SwiftUI

struct RunConfigurationRow: View {
    let configuration: RunConfiguration
    let instance: RunInstance?
    let isSelected: Bool
    let start: () -> Void
    let stop: () -> Void

    private var state: RunInstance.State? { instance?.state }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(configuration.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(RunStatus.label(for: state, startedAt: instance?.startedAt ?? context.date,
                                     now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(RunStatus.indicator(for: state) == .failed
                                     ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            controls
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .help(configuration.command?.command ?? "")
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 2) {
            if instance?.isActive == true {
                iconButton("arrow.clockwise", label: "Reiniciar", action: start)
                    .disabled(state == .stopping)
                iconButton("stop.fill", label: "Parar", action: stop)
                    .disabled(state == .stopping)
            } else {
                iconButton("play.fill", label: "Executar", action: start)
            }
        }
    }

    private func iconButton(_ symbol: String, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    private var dotColor: Color {
        switch RunStatus.indicator(for: state) {
        case .running: .green
        case .busy: .yellow
        case .failed: .red
        case .idle: .gray.opacity(0.5)
        }
    }
}
```

- [ ] **Step 7: Write `RunConfigurationSheet`**

```swift
import SwiftUI

struct RunConfigurationSheet: View {
    enum Target: Identifiable {
        case new
        case edit(RunConfiguration)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let configuration): configuration.id.uuidString
            }
        }
    }

    let root: URL
    let target: Target
    var onSave: (UUID) -> Void

    @Environment(RunConfigurationsModel.self) private var configurations
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var directory = ""
    @State private var attempted = false

    private var editingID: UUID? {
        if case .edit(let configuration) = target { return configuration.id }
        return nil
    }

    private var nameProblem: RunConfigurationsModel.NameProblem? {
        configurations.nameProblem(for: name, excluding: editingID, in: root)
    }

    private var commandMissing: Bool {
        command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var directoryMissing: Bool {
        let resolved = CommandSpec(command: "", workingDirectory: directory, environment: [])
            .resolvedDirectory(in: root)
        var isDirectory: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
                 && isDirectory.boolValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Nome", text: $name, prompt: Text("API"))
                    if attempted, let nameProblem {
                        message(nameProblem == .empty ? "Dê um nome à configuração"
                                                      : "Já existe uma configuração com esse nome",
                                color: .red)
                    }
                    TextField("Comando", text: $command, prompt: Text("npm run dev"), axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 12, design: .monospaced))
                    if attempted, commandMissing {
                        message("Informe o comando", color: .red)
                    }
                    TextField("Pasta", text: $directory, prompt: Text("Raiz do projeto"))
                    if !directory.isEmpty, directoryMissing {
                        message("Essa pasta não existe", color: .orange)
                    }
                } header: {
                    Text(editingID == nil ? "Nova configuração" : "Editar configuração")
                } footer: {
                    Text("O comando roda no seu shell. A pasta é relativa a \(root.lastPathComponent).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editingID == nil ? "Criar" : "Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .onAppear(perform: load)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
    }

    private func load() {
        guard case .edit(let configuration) = target else { return }
        name = configuration.name
        command = configuration.command?.command ?? ""
        directory = configuration.command?.workingDirectory ?? ""
    }

    private func save() {
        attempted = true
        guard nameProblem == nil, !commandMissing else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespaces)
        switch target {
        case .new:
            let created = RunConfiguration(name: trimmedName, kind: .command(CommandSpec(
                command: trimmedCommand, workingDirectory: trimmedDirectory, environment: [])))
            configurations.add(created, to: root)
            onSave(created.id)
        case .edit(let original):
            var updated = original
            updated.name = trimmedName
            updated.kind = .command(CommandSpec(
                command: trimmedCommand, workingDirectory: trimmedDirectory,
                environment: original.command?.environment ?? []))
            configurations.update(updated, in: root)
            onSave(updated.id)
        }
        dismiss()
    }
}
```

- [ ] **Step 8: Write `RunPanel`**

```swift
import AppKit
import SwiftUI

struct RunPanel: View {
    let root: URL
    var close: (() -> Void)?

    @Environment(RunManager.self) private var runs
    @Environment(RunConfigurationsModel.self) private var configurations

    @State private var selectedID: UUID?
    @State private var editor: RunConfigurationSheet.Target?
    @State private var followRequest = 0

    private var items: [RunConfiguration] { configurations.configurations(in: root) }

    private var shownID: UUID? {
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return selectedID }
        return items.first { runs.instance(for: $0.id)?.isActive == true }?.id ?? items.first?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                emptyState
            } else {
                list
                Divider()
                logSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $editor) { target in
            RunConfigurationSheet(root: root, target: target) { selectedID = $0 }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            Text("Execução")
                .font(.system(size: 12, weight: .semibold))
            Text(root.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(root.path)
            Spacer()
            Button { editor = .new } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Nova configuração")
            .accessibilityLabel("Nova configuração")
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Recolher painel (⌥⌘9)")
                .accessibilityLabel("Recolher painel de execução")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Content

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Nenhuma configuração neste projeto")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Configurar…") { editor = .new }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(items) { item in
                    RunConfigurationRow(
                        configuration: item,
                        instance: runs.instance(for: item.id),
                        isSelected: item.id == shownID,
                        start: { run(item) },
                        stop: { Task { await runs.stop(item.id) } })
                    .onTapGesture { selectedID = item.id }
                    .contextMenu {
                        Button("Editar…") { editor = .edit(item) }
                        Button("Remover", role: .destructive) { remove(item) }
                    }
                }
            }
            .padding(6)
        }
        .frame(height: min(CGFloat(items.count) * 32 + 12, 220))
    }

    @ViewBuilder
    private var logSection: some View {
        if let id = shownID, let item = items.first(where: { $0.id == id }) {
            let instance = runs.instance(for: id)
            HStack(spacing: 10) {
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let instance {
                    Button("Copiar") { copy(instance) }
                        .help("Copiar o log inteiro")
                    Button("Limpar") { instance.clearLog() }
                        .help("Limpar o log")
                    Button { followRequest += 1 } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .help("Ir para o fim")
                    .accessibilityLabel("Ir para o fim do log")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            if let instance {
                LogView(instance: instance, followRequest: followRequest)
            } else {
                Text("Clique em \(Image(systemName: "play.fill")) para executar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func run(_ item: RunConfiguration) {
        selectedID = item.id
        followRequest += 1
        Task { await runs.start(item, in: root) }
    }

    private func remove(_ item: RunConfiguration) {
        Task {
            await runs.stop(item.id)
            runs.forget(item.id)
            configurations.remove(item.id, from: root)
        }
    }

    private func copy(_ instance: RunInstance) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instance.log.plainText, forType: .string)
    }
}
```

- [ ] **Step 9: Switch `ChatView` to the pane enum and add the Execução button**

In `DevSpace/Chat/Views/ChatView.swift`:

1. Replace `@AppStorage("DevSpace.gitInspector") private var showChanges = false` by:

```swift
    @AppStorage(InspectorPane.storageKey) private var pane: InspectorPane = .closed
    @State private var lastOpenPane: InspectorPane = .changes
    @Environment(RunManager.self) private var runs
    @Environment(RunConfigurationsModel.self) private var runConfigurations
```

2. Replace the whole `.inspector(isPresented: $showChanges) { … }` modifier by:

```swift
        .inspector(isPresented: inspectorPresented) {
            inspectorContent
        }
```

3. Replace the second `ToolbarItem` (the Alterações button) by the two buttons:

```swift
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggle(.changes)
                } label: {
                    Label {
                        Text("Alterações")
                    } icon: {
                        Image("GitChanges")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }
                .keyboardShortcut("0", modifiers: [.option, .command])
                .help(pane == .changes ? "Ocultar alterações do Git"
                                       : "Mostrar alterações do Git")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggle(.run)
                } label: {
                    Label {
                        Text("Execução")
                    } icon: {
                        Image(systemName: "play.rectangle")
                            .overlay(alignment: .topTrailing) {
                                if runActive {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 3, y: -2)
                                }
                            }
                    }
                }
                .keyboardShortcut("9", modifiers: [.option, .command])
                .help(pane == .run ? "Ocultar execução" : "Mostrar execução")
            }
```

4. In the polling `.task`, replace `showChanges` by `pane == .changes` (both
   in the `id:` string and in the `guard`). In `.onChange(of: chat.isBusy)`,
   replace `if showChanges {` by `if pane == .changes {`.

5. Add these members next to `lightbox`:

```swift
    private var inspectorPresented: Binding<Bool> {
        Binding(get: { pane != .closed }, set: { if !$0 { pane = .closed } })
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if (pane == .closed ? lastOpenPane : pane) == .run {
            RunPanel(root: runRoot, close: { pane = .closed })
                .inspectorColumnWidth(min: 320, ideal: 560, max: 784)
        } else {
            GitChangesPanel(model: gitChanges, directory: chat.workingDirectory,
                            close: { pane = .closed })
                .inspectorColumnWidth(min: 280, ideal: 784, max: 784)
        }
    }

    private var runRoot: URL { runConfigurations.root(for: chat.workingDirectory) }

    private var runActive: Bool {
        runConfigurations.configurations(in: runRoot).contains {
            runs.instance(for: $0.id)?.isActive == true
        }
    }

    private func toggle(_ target: InspectorPane) {
        if pane == target {
            pane = .closed
        } else {
            pane = target
            lastOpenPane = target
        }
    }
```

- [ ] **Step 10: Run the suite**

Expected: TEST SUCCEEDED (including `InspectorPaneTests`).

- [ ] **Step 11: Build the app and try it by hand**

Run: `xcodebuild build -project DevSpace.xcodeproj -scheme DevSpace -destination 'platform=macOS' -derivedDataPath "$DD" 2>&1 | grep -E "error:|warning:|BUILD" | tail -20`
Expected: `** BUILD SUCCEEDED **` with no new warnings in `DevSpace/Run/`.

Then open `"$DD/Build/Products/Debug/DevSpace.app"` and check, in a
conversation whose folder is a real project:

1. ⌥⌘9 opens the Execução panel; ⌥⌘0 swaps to Alterações; clicking the
   active button closes it.
2. "Configurar…" → Nome `Cores`, Comando `ls -G /; printf '\033[31mvermelho\033[0m\n'`
   → Criar. ▶ shows colored output and "Encerrado".
3. A config `ping 127.0.0.1` → ▶: lines arrive live, green dot on the row and
   on the toolbar button; ■ → "Parado".
4. A config with `npm run dev` (or any dev server) → ▶, then ■: the port is
   free right after (`lsof -i :<porta>` returns nothing).
5. Quit the app with a server running: after reopening, the port is free.

- [ ] **Step 12: Bring the spec in line with what was built**

In `docs/superpowers/specs/2026-09-28-run-configurations-design.md`:

1. §4.3: the user-requested stop is its own state, `.stopped`, instead of a
   `requested` flag on `.exited` — same labels and colors.
2. §4.6: record the verification result — with `POSIX_SPAWN_SETSID` the child
   gets its own session and group and `isatty(1)` is true, but macOS does not
   make the pseudo-terminal its controlling terminal (`ps` shows `??`), and
   closing the master does not deliver `SIGHUP`. A crash therefore leaves the
   processes alive; this stays a known limitation.
3. Status line: "Entrega 1 construída".

