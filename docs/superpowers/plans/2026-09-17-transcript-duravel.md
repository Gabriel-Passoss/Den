# Transcript Durável (Etapa 4a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir o registro durável de uma conversa — o artefato que torna possível trocar de harness no meio de uma sessão e continuar.

**Architecture:** Tipos de valor neutros em `HarnessCore` — `Session` contendo `Segment`s, cada um com `TranscriptEntry`s semânticas — mais um `TranscriptStore` cuja primeira implementação é um diretório por sessão: `session.json` com os metadados e um NDJSON append-only por segmento. Nada aqui conhece o Claude Code; o mapper que traduz o formato dele é o plano seguinte.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing. Zero dependências externas.

**Spec:** `docs/superpowers/specs/2026-09-16-devspace-fundacao-design.md` (§4.2 modelo de domínio, §4.3 persistência, §4.1 vocabulário canônico, §7.1 colocação de módulo)

**Escopo:** este plano é a metade neutra da Etapa 4. O `ClaudeEventMapper` é o plano seguinte e consome os 4 fixtures gravados.

## Global Constraints

- Swift tools 6.0; plataforma `.macOS(.v15)`. Concorrência estrita do Swift 6 em vigor.
- **Zero dependências externas** no `Package.swift`.
- Swift Testing (`import Testing`, `@Test`, `#expect`) — não XCTest.
- **Nenhum teste executa o `claude`.** Nada neste plano precisa dele.
- **Sem asserções de tempo de relógio.**
- Estado atual a preservar: 140 testes, build limpo sem warnings, alvo mais lento ~0,15 s.
- Regra estrutural (spec §7.1): **se um tipo não menciona Claude e um segundo adaptador precisaria dele, ele mora em `HarnessCore`.** Tudo neste plano é neutro; nada entra em `ClaudeHarness`.
- Requisito duro (spec §4.2): o transcript é um **registro semântico fiel**, não um log de exibição. O replay depende de ele ser completo.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `Sources/HarnessCore/HarnessID.swift` | identidade de harness, conjunto aberto |
| `Sources/HarnessCore/CanonicalTool.swift` | vocabulário canônico + `ToolCall`/`ToolResult` |
| `Sources/HarnessCore/TranscriptEntry.swift` | a entrada semântica e seus casos |
| `Sources/HarnessCore/Session.swift` | `Session`, `Segment`, `UsageTotals`, `Handoff`, `SessionSummary` |
| `Sources/HarnessCore/TranscriptStore.swift` | o protocolo |
| `Sources/HarnessCore/FileTranscriptStore.swift` | implementação em diretório + NDJSON |

Nenhuma mudança de manifesto: o alvo `HarnessCore` e o `HarnessCoreTests` já existem.

---

### Task 1: `HarnessID` e o vocabulário canônico de ferramentas

**Files:**
- Create: `Sources/HarnessCore/HarnessID.swift`
- Create: `Sources/HarnessCore/CanonicalTool.swift`
- Test: `Tests/HarnessCoreTests/CanonicalToolTests.swift`

**Interfaces:**
- Consumes: `JSONValue` (já existe em `HarnessCore`).
- Produces: `HarnessID` (`RawRepresentable` por `String`, com `.claudeCode`); `CanonicalTool` (enum `String`: `read`, `write`, `edit`, `execute`, `search`, `fetch`); `ToolCall(id:rawName:canonical:input:)`; `ToolResult(callID:isError:content:)`. As Tasks 2, 3 e 4 usam todos.

**Por que `HarnessID` é `String` e não enum:** um enum fechado obrigaria a editar `HarnessCore` para acrescentar um harness — exatamente o acoplamento que a §7.1 existe para impedir. Um adaptador novo declara o próprio id.

**Por que `ToolCall.canonical` é opcional:** nem toda ferramenta de todo harness tem equivalente nos seis verbos. `nil` é a resposta honesta, e o `rawName` mais o `input` preservam o que precisamos. Forçar um mapeamento inventado seria degradar para uma mentira — o mesmo erro que o plano anterior evitou ao manter `PermissionRequest.init?` falível.

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import HarnessCore

@Test func theCanonicalVocabularyIsExactlySixVerbs() {
    #expect(Set(CanonicalTool.allCases.map(\.rawValue))
            == ["read", "write", "edit", "execute", "search", "fetch"])
}

@Test func aHarnessIDIsAnOpenSetSoANewAdapterNeedsNoChangeHere() {
    // Um enum fechado obrigaria a editar HarnessCore para cada harness novo.
    let codex = HarnessID(rawValue: "codex")
    #expect(codex.rawValue == "codex")
    #expect(codex != HarnessID.claudeCode)
    #expect(HarnessID.claudeCode.rawValue == "claude-code")
}

@Test func aToolCallCarriesTheHarnessOwnNameEvenWhenItMapsCleanly() throws {
    let call = ToolCall(id: "toolu_1", rawName: "Edit", canonical: .edit,
                        input: .object(["file_path": .string("/tmp/a")]))
    #expect(call.canonical == .edit)
    #expect(call.rawName == "Edit")
    #expect(call.input["file_path"] == .string("/tmp/a"))
}

@Test func anUnmappableToolIsCarriedWithoutACanonicalVerb() throws {
    // nil é honesto. Inventar um verbo seria degradar para uma mentira.
    let call = ToolCall(id: "toolu_2", rawName: "AlgoQueNaoConhecemos",
                        canonical: nil, input: .object([:]))
    #expect(call.canonical == nil)
    #expect(call.rawName == "AlgoQueNaoConhecemos")
}

@Test func aToolResultPointsBackAtItsCall() {
    let result = ToolResult(callID: "toolu_1", isError: false, content: .string("ok"))
    #expect(result.callID == "toolu_1")
    #expect(!result.isError)
}

@Test func toolTypesSurviveACodableRoundTrip() throws {
    let call = ToolCall(id: "t", rawName: "Bash", canonical: .execute,
                        input: .object(["command": .string("ls"), "n": .int(1)]))
    let data = try JSONEncoder().encode(call)
    #expect(try JSONDecoder().decode(ToolCall.self, from: data) == call)

    let unmapped = ToolCall(id: "u", rawName: "X", canonical: nil, input: .null)
    let unmappedData = try JSONEncoder().encode(unmapped)
    #expect(try JSONDecoder().decode(ToolCall.self, from: unmappedData) == unmapped)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter CanonicalTool`
Expected: FAIL — `cannot find 'CanonicalTool' in scope`.

- [ ] **Step 3: Implementar `HarnessID`**

```swift
/// Qual harness hospeda um trecho de conversa.
///
/// É um conjunto ABERTO, não um enum: um enum fechado obrigaria a editar
/// `HarnessCore` para acrescentar um harness, que é exatamente o acoplamento
/// que a spec §7.1 existe para impedir. Cada adaptador declara o próprio id.
public struct HarnessID: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let claudeCode = HarnessID(rawValue: "claude-code")
}
```

- [ ] **Step 4: Implementar o vocabulário**

```swift
/// Os verbos que atravessam harnesses.
///
/// Harnesses nomeiam ferramentas de forma diferente — `Edit` num, outra coisa
/// noutro — e o replay depende de significado equivalente entre eles. O
/// canônico serve ao handoff e à UI; o `rawName` e o `input` garantem que nada
/// é perdido (spec §4.1).
public enum CanonicalTool: String, Sendable, Equatable, CaseIterable, Codable {
    case read
    case write
    case edit
    case execute
    case search
    case fetch
}

/// Uma chamada de ferramenta, como o harness a pediu.
public struct ToolCall: Sendable, Equatable, Codable {
    /// O id que o harness usa para casar chamada e resultado.
    public let id: String
    /// O nome que o harness deu, preservado literalmente.
    public let rawName: String
    /// O verbo equivalente, quando existe.
    ///
    /// `nil` quando não conhecemos equivalente. É a resposta honesta: inventar
    /// um verbo faria o handoff mandar ao próximo harness uma instrução que
    /// ninguém pediu.
    public let canonical: CanonicalTool?
    public let input: JSONValue

    public init(id: String, rawName: String, canonical: CanonicalTool?, input: JSONValue) {
        self.id = id
        self.rawName = rawName
        self.canonical = canonical
        self.input = input
    }
}

/// O resultado de uma chamada de ferramenta.
public struct ToolResult: Sendable, Equatable, Codable {
    /// O `ToolCall.id` a que este resultado responde.
    public let callID: String
    public let isError: Bool
    public let content: JSONValue

    public init(callID: String, isError: Bool, content: JSONValue) {
        self.callID = callID
        self.isError = isError
        self.content = content
    }
}
```

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter CanonicalTool`
Expected: PASS, 6 testes.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): identidade de harness e vocabulário canônico de ferramentas"
```

---

### Task 2: `TranscriptEntry` — a entrada semântica

**Files:**
- Create: `Sources/HarnessCore/TranscriptEntry.swift`
- Test: `Tests/HarnessCoreTests/TranscriptEntryTests.swift`

**Interfaces:**
- Consumes: `JSONValue`, `ToolCall`, `ToolResult` (Task 1), `PermissionRequest`, `PermissionDecision` (já em `HarnessCore`).
- Produces: `TranscriptEntry(id:timestamp:kind:raw:)` com `TranscriptEntry.Kind` de nove casos, mais `Attachment` e `TurnResult`. As Tasks 3, 4 e 5 usam.

Os nove casos vêm da spec §4.2, literalmente: `userMessage`, `assistantText`, `assistantThinking`, `toolCall`, `toolResult`, `permissionRequest`, `permissionDecision`, `systemNotice`, `turnResult`.

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import HarnessCore

private let fixedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private func roundTrip(_ entry: TranscriptEntry) throws -> TranscriptEntry {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TranscriptEntry.self, from: try encoder.encode(entry))
}

@Test func everyKindSurvivesARoundTrip() throws {
    let kinds: [TranscriptEntry.Kind] = [
        .userMessage(text: "oi", attachments: []),
        .assistantText("olá"),
        .assistantThinking("hmm"),
        .toolCall(ToolCall(id: "t1", rawName: "Bash", canonical: .execute,
                           input: .object(["command": .string("ls")]))),
        .toolResult(ToolResult(callID: "t1", isError: false, content: .string("a\nb"))),
        .permissionRequest(PermissionRequest(
            id: "r1", toolName: "Write", displayName: "Write", description: nil,
            input: .object([:]), toolUseID: "t2", suggestions: [])),
        .permissionDecision(requestID: "r1", .allow(updatedInput: nil)),
        .systemNotice(subtype: "init", text: "sessão iniciada"),
        .turnResult(TurnResult(usage: UsageTotals(inputTokens: 10, outputTokens: 20,
                                                  cacheReadTokens: 0, cacheCreationTokens: 0,
                                                  costUSD: 0.01),
                               stopReason: "end_turn", isError: false)),
    ]
    for kind in kinds {
        let entry = TranscriptEntry(id: fixedID, timestamp: fixedDate, kind: kind, raw: .null)
        #expect(try roundTrip(entry) == entry, "caso não sobreviveu: \(kind)")
    }
}

@Test func theRawPayloadIsPreservedWholeNotSummarized() throws {
    // Spec §4.1: o canônico serve ao handoff e à UI; o raw garante que nada é
    // perdido. Um raw resumido quebraria o replay.
    let raw = JSONValue.object([
        "type": .string("assistant"),
        "message": .object(["role": .string("assistant"), "extra": .int(7)]),
    ])
    let entry = TranscriptEntry(id: fixedID, timestamp: fixedDate,
                                kind: .assistantText("olá"), raw: raw)
    #expect(try roundTrip(entry).raw == raw)
    #expect(try roundTrip(entry).raw["message"]?["extra"] == .int(7))
}

@Test func twoEntriesWithDifferentIDsAreNotEqual() {
    let a = TranscriptEntry(id: UUID(), timestamp: fixedDate, kind: .assistantText("x"), raw: .null)
    let b = TranscriptEntry(id: UUID(), timestamp: fixedDate, kind: .assistantText("x"), raw: .null)
    #expect(a != b)
}

@Test func anAttachmentCarriesItsPathAndKind() throws {
    let entry = TranscriptEntry(
        id: fixedID, timestamp: fixedDate,
        kind: .userMessage(text: "veja", attachments: [
            Attachment(kind: "image", path: "/tmp/a.png", raw: .null),
        ]),
        raw: .null)
    guard case .userMessage(_, let attachments) = try roundTrip(entry).kind else {
        Issue.record("esperava userMessage"); return
    }
    #expect(attachments.first?.path == "/tmp/a.png")
    #expect(attachments.first?.kind == "image")
}

@Test func usageTotalsAdd() {
    let a = UsageTotals(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3,
                        cacheCreationTokens: 4, costUSD: 0.5)
    let b = UsageTotals(inputTokens: 10, outputTokens: 20, cacheReadTokens: 30,
                        cacheCreationTokens: 40, costUSD: 1.5)
    let sum = a + b
    #expect(sum.inputTokens == 11)
    #expect(sum.outputTokens == 22)
    #expect(sum.cacheReadTokens == 33)
    #expect(sum.cacheCreationTokens == 44)
    #expect(sum.costUSD == 2.0)
    #expect(UsageTotals.zero + a == a)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter TranscriptEntry`
Expected: FAIL — `cannot find 'TranscriptEntry' in scope`.

- [ ] **Step 3: Implementar**

```swift
import Foundation

/// Um anexo de uma mensagem do usuário.
public struct Attachment: Sendable, Equatable, Codable {
    /// Como o harness classificou o anexo ("image", "file", …), literal.
    public let kind: String
    public let path: String
    public let raw: JSONValue

    public init(kind: String, path: String, raw: JSONValue) {
        self.kind = kind
        self.path = path
        self.raw = raw
    }
}

/// Contabilidade de tokens e custo.
///
/// Fica por segmento e é agregada por sessão, porque tokens acabam POR
/// PROVEDOR — que é a razão original de existir a troca de harness (spec §4.2).
public struct UsageTotals: Sendable, Equatable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int
    public var costUSD: Double

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0,
                cacheCreationTokens: Int = 0, costUSD: Double = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.costUSD = costUSD
    }

    public static let zero = UsageTotals()

    public static func + (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
        UsageTotals(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
            costUSD: lhs.costUSD + rhs.costUSD
        )
    }
}

/// Como um turno terminou.
public struct TurnResult: Sendable, Equatable, Codable {
    public let usage: UsageTotals
    public let stopReason: String?
    public let isError: Bool

    public init(usage: UsageTotals, stopReason: String?, isError: Bool) {
        self.usage = usage
        self.stopReason = stopReason
        self.isError = isError
    }
}

/// Uma entrada do transcript.
///
/// Semântica, não visual: a spec §4.2 exige um registro semântico FIEL, porque
/// o replay para outro harness depende de ele ser completo. Cada entrada
/// carrega o payload original em `raw` — o canônico serve ao handoff e à UI, o
/// raw garante que nada é perdido.
public struct TranscriptEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    /// O payload original do harness, na íntegra.
    public let raw: JSONValue

    public init(id: UUID = UUID(), timestamp: Date, kind: Kind, raw: JSONValue) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.raw = raw
    }

    /// Os nove casos da spec §4.2.
    public enum Kind: Sendable, Equatable, Codable {
        case userMessage(text: String, attachments: [Attachment])
        case assistantText(String)
        case assistantThinking(String)
        case toolCall(ToolCall)
        case toolResult(ToolResult)
        case permissionRequest(PermissionRequest)
        case permissionDecision(requestID: String, PermissionDecision)
        case systemNotice(subtype: String, text: String)
        case turnResult(TurnResult)
    }
}
```

**Você precisará acrescentar `Codable` a três tipos existentes.** Verificado: em
`Sources/HarnessCore/Permission.swift`, `PermissionRequest`,
`PermissionSuggestion` e `PermissionDecision` são declarados
`Equatable, Sendable` e **não** `Codable`. `TranscriptEntry.Kind` os embute e
precisa ser `Codable`, então acrescente a conformidade na declaração de cada um
— são tipos de valor cujos membros já são `Codable` (`String`, `JSONValue`,
`Bool`), então a síntese do compilador basta.

Os três já têm inicializadores públicos de membro, então nada mais é preciso.
Relate a mudança: ela amplia a superfície pública de um arquivo que outro plano
criou.

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter TranscriptEntry`
Expected: PASS, 5 testes.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `cd Packages/HarnessKit && swift test`
Expected: tudo verde, sem regressão.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): TranscriptEntry, a entrada semântica do transcript"
```

---

### Task 3: `Session` e `Segment`

**Files:**
- Create: `Sources/HarnessCore/Session.swift`
- Test: `Tests/HarnessCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: `HarnessID` (Task 1), `TranscriptEntry`, `UsageTotals` (Task 2).
- Produces: `Session(id:title:workingDirectory:segments:)` com `.totalUsage` e `.allEntries`; `Segment(id:harness:harnessSessionID:model:entries:usage:seededBy:)`; `Handoff`; `SessionSummary`. As Tasks 4 e 5 usam.

**A ideia central desta task**, e a razão de a Etapa 4 existir: *uma sessão do DevSpace não é uma sessão do harness.* Trocar de Claude para Codex fecha um `Segment` e abre outro dentro da **mesma** `Session`. O transcript da sessão é a concatenação dos segmentos, e a proveniência da troca fica registrada em `seededBy`.

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import HarnessCore

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .null)
}

private func segment(
    _ harness: HarnessID,
    entries: [TranscriptEntry] = [],
    usage: UsageTotals = .zero,
    seededBy: Handoff? = nil
) -> Segment {
    Segment(id: UUID(), harness: harness, harnessSessionID: UUID(),
            model: "algum-modelo", entries: entries, usage: usage, seededBy: seededBy)
}

@Test func oneSessionSpansSeveralHarnesses() {
    // A ideia central: a conversa é nossa; cada harness hospeda um trecho.
    let session = Session(
        id: UUID(), title: "refatorar o webhook",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        segments: [
            segment(.claudeCode, entries: [entry("um"), entry("dois")]),
            segment(HarnessID(rawValue: "codex"), entries: [entry("três")],
                    seededBy: .briefing("resumo do que foi feito")),
        ])
    #expect(session.segments.count == 2)
    #expect(session.allEntries.map(\.id).count == 3)
    #expect(session.segments.map(\.harness) == [.claudeCode, HarnessID(rawValue: "codex")])
}

@Test func theTranscriptIsTheConcatenationOfItsSegmentsInOrder() {
    let session = Session(
        id: UUID(), title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
        segments: [
            segment(.claudeCode, entries: [entry("a"), entry("b")]),
            segment(.claudeCode, entries: [entry("c")]),
        ])
    let texts = session.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["a", "b", "c"])
}

@Test func usageAggregatesAcrossSegmentsBecauseTokensRunOutPerProvider() {
    let session = Session(
        id: UUID(), title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
        segments: [
            segment(.claudeCode, usage: UsageTotals(inputTokens: 100, outputTokens: 10, costUSD: 1)),
            segment(HarnessID(rawValue: "codex"),
                    usage: UsageTotals(inputTokens: 50, outputTokens: 5, costUSD: 0.5)),
        ])
    #expect(session.totalUsage.inputTokens == 150)
    #expect(session.totalUsage.outputTokens == 15)
    #expect(session.totalUsage.costUSD == 1.5)
}

@Test func aHandoffRecordsHowTheNextSegmentWasSeeded() throws {
    let briefed = segment(.claudeCode, seededBy: .briefing("o que já foi feito"))
    let target = UUID()
    let replayed = segment(.claudeCode, seededBy: .replay(throughEntry: target))
    #expect(briefed.seededBy == .briefing("o que já foi feito"))
    #expect(replayed.seededBy == .replay(throughEntry: target))
    #expect(segment(.claudeCode).seededBy == nil)
}

@Test func aSessionSurvivesACodableRoundTrip() throws {
    let session = Session(
        id: UUID(), title: "com acentuação é", workingDirectory: URL(fileURLWithPath: "/tmp/a b"),
        segments: [segment(.claudeCode, entries: [entry("x")],
                           usage: UsageTotals(inputTokens: 3), seededBy: .briefing("b"))])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let back = try decoder.decode(Session.self, from: try encoder.encode(session))
    #expect(back == session)
    #expect(back.workingDirectory.path == "/tmp/a b")
}

@Test func aSummaryDescribesASessionWithoutItsEntries() {
    let session = Session(
        id: UUID(), title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
        segments: [
            segment(.claudeCode, entries: [entry("a"), entry("b")],
                    usage: UsageTotals(inputTokens: 7)),
            segment(HarnessID(rawValue: "codex"), entries: [entry("c")]),
        ])
    let summary = SessionSummary(session: session, updatedAt: when)
    #expect(summary.id == session.id)
    #expect(summary.entryCount == 3)
    #expect(summary.harnesses == [.claudeCode, HarnessID(rawValue: "codex")])
    #expect(summary.usage.inputTokens == 7)
    #expect(summary.updatedAt == when)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter SessionTests`
Expected: FAIL — `cannot find 'Session' in scope`.

- [ ] **Step 3: Implementar**

```swift
import Foundation

/// Como o próximo segmento foi semeado ao trocar de harness.
///
/// As duas estratégias da spec §3: o usuário escolhe entre um briefing gerado
/// e o replay do transcript.
public enum Handoff: Sendable, Equatable, Codable {
    /// Um resumo estruturado, gerado a partir do transcript anterior.
    case briefing(String)
    /// O transcript reinjetado até uma entrada específica, inclusive.
    ///
    /// Referencia a entrada por id e não por índice: índices se deslocam,
    /// ids não.
    case replay(throughEntry: UUID)
}

/// Um trecho contínuo de conversa dentro de um harness.
public struct Segment: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let harness: HarnessID
    /// O `--session-id` que NÓS geramos e demos ao harness.
    public let harnessSessionID: UUID
    public var model: String
    public var entries: [TranscriptEntry]
    /// Tokens e custo deste trecho. Fica aqui, e não na sessão, porque tokens
    /// acabam por provedor.
    public var usage: UsageTotals
    /// Como este segmento foi semeado, quando veio de uma troca de harness.
    /// `nil` no primeiro segmento de uma sessão.
    public var seededBy: Handoff?

    public init(id: UUID = UUID(), harness: HarnessID, harnessSessionID: UUID,
                model: String, entries: [TranscriptEntry] = [],
                usage: UsageTotals = .zero, seededBy: Handoff? = nil) {
        self.id = id
        self.harness = harness
        self.harnessSessionID = harnessSessionID
        self.model = model
        self.entries = entries
        self.usage = usage
        self.seededBy = seededBy
    }
}

/// O que o usuário chama de "a conversa".
///
/// **Uma sessão do DevSpace não é uma sessão do harness.** Trocar de Claude
/// para Codex fecha um `Segment` e abre outro dentro desta mesma `Session`; o
/// transcript é a concatenação deles e a proveniência da troca fica em
/// `Segment.seededBy` (spec §4.2).
public struct Session: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var workingDirectory: URL
    /// Ordenados. O primeiro é o mais antigo.
    public var segments: [Segment]

    public init(id: UUID = UUID(), title: String, workingDirectory: URL,
                segments: [Segment] = []) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.segments = segments
    }

    /// O transcript inteiro, atravessando harnesses.
    public var allEntries: [TranscriptEntry] {
        segments.flatMap(\.entries)
    }

    /// Custo somado de todos os segmentos.
    public var totalUsage: UsageTotals {
        segments.reduce(.zero) { $0 + $1.usage }
    }
}

/// O bastante para listar uma sessão sem carregar o transcript dela.
public struct SessionSummary: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var workingDirectory: URL
    /// Na ordem em que apareceram na conversa.
    public var harnesses: [HarnessID]
    public var usage: UsageTotals
    public var entryCount: Int
    public var updatedAt: Date

    public init(id: UUID, title: String, workingDirectory: URL, harnesses: [HarnessID],
                usage: UsageTotals, entryCount: Int, updatedAt: Date) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.harnesses = harnesses
        self.usage = usage
        self.entryCount = entryCount
        self.updatedAt = updatedAt
    }

    public init(session: Session, updatedAt: Date) {
        self.init(id: session.id, title: session.title,
                  workingDirectory: session.workingDirectory,
                  harnesses: session.segments.map(\.harness),
                  usage: session.totalUsage,
                  entryCount: session.allEntries.count,
                  updatedAt: updatedAt)
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter SessionTests`
Expected: PASS, 6 testes.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): Session e Segment — a conversa é nossa, o harness hospeda um trecho"
```

---

### Task 4: `TranscriptStore` e a implementação em arquivo

**Files:**
- Create: `Sources/HarnessCore/TranscriptStore.swift`
- Create: `Sources/HarnessCore/FileTranscriptStore.swift`
- Test: `Tests/HarnessCoreTests/FileTranscriptStoreTests.swift`

**Interfaces:**
- Consumes: `Session`, `Segment`, `SessionSummary` (Task 3), `TranscriptEntry` (Task 2).
- Produces: `protocol TranscriptStore` com `saveMetadata(_:)`, `append(_:to:in:)`, `load(_:)`, `list()`; e `FileTranscriptStore(root:)`. A Task 5 estende esta implementação.

**Desvio da spec, deliberado e a registrar no commit:** a §4.3 escreve
`func append(_ entry: TranscriptEntry, to: Segment.ID)`. Essa assinatura não
consegue localizar o arquivo: o layout é um diretório por sessão, e um id de
segmento sozinho não diz em qual sessão ele está. Acrescentamos `in sessionID:`.
A alternativa seria um índice de segmento→sessão, que é estado a manter
sincronizado para evitar passar um parâmetro.

**Layout em disco:**

```
<root>/<session-uuid>/session.json        metadados: título, diretório, segmentos SEM entradas
<root>/<session-uuid>/<segment-uuid>.ndjson   uma entrada por linha
```

`session.json` guarda os segmentos com `entries: []`. As entradas moram só nos
NDJSON. `load` lê os metadados e preenche as entradas; `list` lê **apenas** os
`session.json`, que é o que mantém a listagem barata.

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import HarnessCore

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("transcript-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .object(["t": .string(text)]))
}

private func newSession(segments: [Segment]) -> Session {
    Session(title: "uma conversa", workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            segments: segments)
}

private func newSegment(_ harness: HarnessID = .claudeCode) -> Segment {
    Segment(harness: harness, harnessSessionID: UUID(), model: "m")
}

@Test func aSessionRoundTripsThroughDisk() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.id == session.id)
    #expect(loaded.title == "uma conversa")
    #expect(loaded.workingDirectory.path == "/tmp/repo")
    #expect(loaded.segments.count == 1)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "dois"])
}

@Test func theRawPayloadSurvivesDisk() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("x"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.allEntries.first?.raw["t"] == .string("x"))
}

@Test func entriesFromDifferentSegmentsDoNotMix() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let first = newSegment(.claudeCode)
    let second = newSegment(HarnessID(rawValue: "codex"))
    let session = newSession(segments: [first, second])
    try await store.saveMetadata(session)
    try await store.append(entry("claude-um"), to: first.id, in: session.id)
    try await store.append(entry("codex-um"), to: second.id, in: session.id)
    try await store.append(entry("claude-dois"), to: first.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.segments[0].entries.count == 2)
    #expect(loaded.segments[1].entries.count == 1)
    #expect(loaded.segments[1].harness == HarnessID(rawValue: "codex"))
}

@Test func theFileOnDiskIsOneJSONObjectPerLine() async throws {
    // O formato tem que ser legível com `cat` quando algo der errado (spec §4.3).
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let lines = try String(contentsOf: file, encoding: .utf8)
        .split(separator: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 2)
    for line in lines {
        #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil)
    }
}

@Test func listReturnsASummaryPerSession() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let a = newSession(segments: [newSegment()])
    let b = newSession(segments: [newSegment()])
    try await store.saveMetadata(a)
    try await store.saveMetadata(b)

    let summaries = try await store.list()
    #expect(summaries.count == 2)
    #expect(Set(summaries.map(\.id)) == Set([a.id, b.id]))
}

@Test func savingMetadataAgainDoesNotDisturbTheEntries() async throws {
    // Renomear a sessão não pode apagar o transcript.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    var session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)

    session.title = "outro título"
    try await store.saveMetadata(session)

    let loaded = try await store.load(session.id)
    #expect(loaded.title == "outro título")
    #expect(loaded.allEntries.count == 1)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter FileTranscriptStore`
Expected: FAIL — `cannot find 'FileTranscriptStore' in scope`.

- [ ] **Step 3: Implementar o protocolo**

```swift
import Foundation

/// Onde o transcript vive.
///
/// É a costura da spec §4.3: a primeira implementação é NDJSON em disco, e
/// quando listar ficar lento ou houver busca por conteúdo, o SQLite entra sem
/// que nada acima perceba.
public protocol TranscriptStore: Sendable {
    /// Grava os metadados da sessão — título, diretório e os segmentos SEM as
    /// entradas. Idempotente: chamar de novo não perturba o transcript.
    func saveMetadata(_ session: Session) async throws

    /// Acrescenta uma entrada ao fim do segmento.
    ///
    /// - Note: a spec §4.3 escreve esta assinatura sem `sessionID`. O layout é
    ///   um diretório por sessão, e um id de segmento sozinho não diz em qual
    ///   sessão ele está — a alternativa seria manter um índice sincronizado
    ///   para poupar um parâmetro.
    func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                in sessionID: Session.ID) async throws

    /// A sessão inteira, com o transcript.
    func load(_ sessionID: Session.ID) async throws -> Session

    /// Uma linha por sessão, sem carregar transcript nenhum.
    func list() async throws -> [SessionSummary]
}
```

- [ ] **Step 4: Implementar o store em arquivo**

```swift
import Foundation

/// Um diretório por sessão: `session.json` com os metadados e um NDJSON
/// append-only por segmento.
///
/// Zero dependências, legível com `cat` quando algo der errado, e natural para
/// um log append-only (spec §4.3).
public actor FileTranscriptStore: TranscriptStore {
    public enum StoreError: Error, Equatable {
        case sessionNotFound(UUID)
        case segmentNotFound(UUID)
    }

    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Uma entrada por linha: nada de pretty-printing no NDJSON.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private func directory(for sessionID: UUID) -> URL {
        root.appendingPathComponent(sessionID.uuidString)
    }

    private func metadataFile(for sessionID: UUID) -> URL {
        directory(for: sessionID).appendingPathComponent("session.json")
    }

    private func segmentFile(_ segmentID: UUID, in sessionID: UUID) -> URL {
        directory(for: sessionID).appendingPathComponent("\(segmentID.uuidString).ndjson")
    }

    public func saveMetadata(_ session: Session) throws {
        try FileManager.default.createDirectory(
            at: directory(for: session.id), withIntermediateDirectories: true)
        // As entradas moram nos NDJSON; os metadados guardam os segmentos vazios.
        var stripped = session
        stripped.segments = session.segments.map {
            var segment = $0
            segment.entries = []
            return segment
        }
        try encoder.encode(stripped).write(to: metadataFile(for: session.id), options: .atomic)
    }

    public func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                       in sessionID: Session.ID) throws {
        let file = segmentFile(segmentID, in: sessionID)
        var line = try encoder.encode(entry)
        line.append(0x0A)

        let manager = FileManager.default
        if !manager.fileExists(atPath: file.path) {
            try manager.createDirectory(at: directory(for: sessionID),
                                        withIntermediateDirectories: true)
            try line.write(to: file, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func load(_ sessionID: Session.ID) throws -> Session {
        let metadata = metadataFile(for: sessionID)
        guard FileManager.default.fileExists(atPath: metadata.path) else {
            throw StoreError.sessionNotFound(sessionID)
        }
        var session = try decoder.decode(Session.self, from: Data(contentsOf: metadata))
        session.segments = try session.segments.map { segment in
            var filled = segment
            filled.entries = try entries(of: segment.id, in: sessionID)
            return filled
        }
        return session
    }

    public func list() throws -> [SessionSummary] {
        let manager = FileManager.default
        guard let directories = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return directories.compactMap { directory in
            let metadata = directory.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: metadata),
                  let session = try? decoder.decode(Session.self, from: data)
            else { return nil }
            let modified = (try? metadata.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date(timeIntervalSince1970: 0)
            // O metadado guarda segmentos SEM entradas, então
            // `SessionSummary(session:)` contaria zero. A contagem vem das
            // linhas dos NDJSON — barata, sem decodificar nada.
            let count = session.segments.reduce(0) { total, segment in
                total + lineCount(of: segment.id, in: session.id)
            }
            return SessionSummary(
                id: session.id, title: session.title,
                workingDirectory: session.workingDirectory,
                harnesses: session.segments.map(\.harness),
                usage: session.totalUsage, entryCount: count, updatedAt: modified)
        }
    }

    private func entries(of segmentID: UUID, in sessionID: UUID) throws -> [TranscriptEntry] {
        let file = segmentFile(segmentID, in: sessionID)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return try text.split(separator: "\n")
            .filter { !$0.isEmpty }
            .map { try decoder.decode(TranscriptEntry.self, from: Data($0.utf8)) }
    }

    private func lineCount(of segmentID: UUID, in sessionID: UUID) -> Int {
        guard let text = try? String(contentsOf: segmentFile(segmentID, in: sessionID),
                                     encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { !$0.isEmpty }.count
    }
}
```

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter FileTranscriptStore`
Expected: PASS, 6 testes.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): TranscriptStore e a implementação em NDJSON

A assinatura de append acrescenta o sessionID em relação à spec §4.3: o layout
é um diretório por sessão, e um id de segmento sozinho não localiza o arquivo.
A alternativa seria um índice segmento→sessão a manter sincronizado."
```

---

### Task 5: O store sobrevive a um processo que morreu no meio

**Files:**
- Modify: `Sources/HarnessCore/FileTranscriptStore.swift`
- Test: `Tests/HarnessCoreTests/FileTranscriptStoreResilienceTests.swift`

**Interfaces:**
- Consumes: tudo da Task 4.
- Produces: nenhuma assinatura nova. Muda o comportamento de `load` e `list` diante de arquivo corrompido, e acrescenta `StoreError.sessionNotFound`.

**Por que esta task existe:** um NDJSON append-only é escrito enquanto o app roda. Se o DevSpace for morto no meio de uma escrita, a última linha fica pela metade. Um `load` que falhe inteiro nesse caso perde uma conversa inteira por causa de meia linha — e é exatamente quando o usuário mais quer o histórico de volta. A regra é a mesma da spec §5.4: **degradar, não falhar.**

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import HarnessCore

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("resilience-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .null)
}

@Test func aTruncatedLastLineCostsOneEntryNotTheWholeSession() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: .claudeCode, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    // Simula o processo morto no meio de uma escrita.
    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"não termi"#.utf8))
    try handle.close()

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "dois"], "meia linha não pode custar a conversa inteira")
}

@Test func aCorruptLineInTheMiddleDoesNotHideTheOnesAfterIt() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: .claudeCode, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{lixo}\n".utf8))
    try handle.close()
    try await store.append(entry("tres"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "tres"])
}

@Test func aSegmentWithNoFileYetLoadsAsEmpty() async throws {
    // Um segmento recém-aberto ainda não tem arquivo. Isso é normal, não erro.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: .claudeCode, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)

    let loaded = try await store.load(session.id)
    #expect(loaded.segments.first?.entries.isEmpty == true)
}

@Test func loadingAnUnknownSessionSaysSoInsteadOfCrashing() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let missing = UUID()
    await #expect(throws: FileTranscriptStore.StoreError.sessionNotFound(missing)) {
        _ = try await store.load(missing)
    }
}

@Test func listSkipsADirectoryWithoutValidMetadata() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let good = Session(title: "boa", workingDirectory: URL(fileURLWithPath: "/tmp"), segments: [])
    try await store.saveMetadata(good)

    let junk = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
    try Data("{não sou json".utf8).write(to: junk.appendingPathComponent("session.json"))
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("nem-diretorio-de-sessao"),
        withIntermediateDirectories: true)

    let summaries = try await store.list()
    #expect(summaries.map(\.id) == [good.id])
}

@Test func listOnAnEmptyOrMissingRootIsEmptyNotAnError() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try await FileTranscriptStore(root: root).list().isEmpty)

    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nao-existe-\(UUID().uuidString)")
    #expect(try await FileTranscriptStore(root: missing).list().isEmpty)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter Resilience`
Expected: FAIL — o `load` lança ao encontrar a linha truncada, e `sessionNotFound` não existe.

- [ ] **Step 3: Tornar a leitura tolerante**

Troque o `entries(of:in:)` da Task 4 por uma versão que pula a linha ruim em vez de derrubar a leitura:

```swift
    /// Lê as entradas de um segmento, pulando linhas ilegíveis.
    ///
    /// Um NDJSON append-only é escrito com o app rodando: se o processo morrer
    /// no meio de uma escrita, a última linha fica pela metade. Falhar a
    /// leitura inteira perderia a conversa por causa de meia linha — e é
    /// justamente quando o usuário mais quer o histórico de volta. Mesma regra
    /// da spec §5.4: degradar, não falhar.
    ///
    /// - Note: a entrada ilegível é perdida, não recuperada. Se o transcript
    ///   precisar um dia ser à prova de perda, o caminho é escrever tamanho +
    ///   linha, não tentar reparar JSON.
    private func entries(of segmentID: UUID, in sessionID: UUID) -> [TranscriptEntry] {
        let file = segmentFile(segmentID, in: sessionID)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .filter { !$0.isEmpty }
            .compactMap { try? decoder.decode(TranscriptEntry.self, from: Data($0.utf8)) }
    }
```

E o `load` passa a checar a existência dos metadados:

```swift
    public func load(_ sessionID: Session.ID) throws -> Session {
        let metadata = metadataFile(for: sessionID)
        guard let data = try? Data(contentsOf: metadata) else {
            throw StoreError.sessionNotFound(sessionID)
        }
        var session = try decoder.decode(Session.self, from: data)
        session.segments = session.segments.map { segment in
            var filled = segment
            filled.entries = entries(of: segment.id, in: sessionID)
            return filled
        }
        return session
    }
```

O `list` da Task 4 já usa `try?` em cada diretório, então ele ignora metadados
inválidos sem mudança. Confirme rodando o teste.

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter Resilience`
Expected: PASS, 6 testes.

- [ ] **Step 5: Verificar que a tolerância não escondeu um bug de escrita**

Uma leitura que pula linhas ruins pode mascarar um `append` que produz lixo.
Confirme que o caminho feliz ainda é exato:

Run: `cd Packages/HarnessKit && swift test --filter FileTranscriptStore`
Expected: PASS — os 6 testes da Task 4 continuam verdes, incluindo o que afirma
uma linha JSON válida por entrada.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `cd Packages/HarnessKit && swift build && swift test`
Expected: build limpo sem warnings, tudo verde, alvo mais lento sem regressão perceptível.

- [ ] **Step 7: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): o store sobrevive a um processo morto no meio de uma escrita

Uma linha truncada custa uma entrada, não a conversa inteira. Mesma regra da
spec §5.4: degradar, não falhar."
```

---

## Ao fim deste plano

Existe: o modelo de domínio neutro que a troca de harness depende, o vocabulário
canônico de ferramentas, e um store que escreve e relê um transcript — e
sobrevive a um processo morto no meio.

Não existe, por decisão: o `ClaudeEventMapper`. É o plano seguinte, e ele
consome os 4 fixtures já gravados, então se verifica sem gastar um centavo.

**O que o plano seguinte terá de decidir**, e que vale entrar nele com os olhos
abertos: o corpus tem 298 `stream_event` contra 17 linhas `assistant`, porque o
texto do assistente chega duas vezes — incremental e completo. O mapper decide a
fonte por destino, ou o transcript duplica cada turno. A spec §4.4 já fixou a
regra (`SessionEvent` efêmero para a UI, `TranscriptEntry` durável consolidado);
o plano seguinte a implementa.
