import Foundation
import Workflow

enum TaskJournal {
    static func stored(_ history: [Movement]) -> String {
        (try? JSONText.encode(history.map(StoredMovement.init), as: .document)) ?? "[]"
    }

    static func history(from text: String) -> [Movement] {
        let items = JSONText.decode([Tolerant<StoredMovement>].self, from: text, as: .document) ?? []
        return items.compactMap { $0.value?.movement }
    }

    static func stored(_ pendencies: [Pendency]) -> String {
        (try? JSONText.encode(pendencies.map(StoredPendency.init), as: .document)) ?? "[]"
    }

    static func pendencies(from text: String) -> [Pendency] {
        guard let items = JSONText.decode([ReadPendency].self, from: text, as: .document) else {
            return [.unreadable()]
        }
        return items.map(\.pendency)
    }
}

private extension Pendency {
    static func unreadable(_ id: UUID? = nil) -> Pendency {
        Pendency(id: id.map(PendencyID.init) ?? PendencyID(), kind: .problem(.executionFailed("pendência ilegível")))
    }
}

private struct ReadPendency: Decodable {
    let pendency: Pendency

    init(from decoder: any Decoder) {
        if let pendency = (try? StoredPendency(from: decoder))?.pendency {
            self.pendency = pendency
        } else {
            let id = try? decoder.container(keyedBy: StoredPendency.CodingKeys.self).decode(UUID.self, forKey: .id)
            pendency = .unreadable(id)
        }
    }
}

private struct Tolerant<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) {
        value = try? Wrapped(from: decoder)
    }
}

private struct StoredPendency: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, decision, passage, destination, problem, refusal, subtask, message
    }

    private static let decisions: [String: Decision] = ["permission": .permission, "question": .question]

    private static let refusals: [String: MoveRefusal] = [
        "unknownStage": .unknownStage, "sameStage": .sameStage,
        "missingPassage": .missingPassage, "openSubtasks": .openSubtasks,
    ]

    let id: UUID
    var kind = ""
    var decision: String?
    var passage: String?
    var destination: UUID?
    var problem: String?
    var refusal: String?
    var subtask: UUID?
    var message: String?

    init(_ pendency: Pendency) {
        id = pendency.id.rawValue
        switch pendency.kind {
        case .decision(let decision):
            kind = "decision"
            self.decision = Self.decisions.first { $0.value == decision }?.key
        case .stageFinished:
            kind = "stageFinished"
        case .returned(let passage):
            kind = "returned"
            self.passage = passage.text
        case .chainLimitReached(let destination, let passage):
            kind = "chainLimitReached"
            self.destination = destination.rawValue
            self.passage = passage.text
        case .problem(let problem):
            kind = "problem"
            store(problem)
        }
    }

    private mutating func store(_ problem: Problem) {
        switch problem {
        case .moveRefused(let refusal):
            self.problem = "moveRefused"
            self.refusal = Self.refusals.first { $0.value == refusal }?.key
        case .passageFailed:
            self.problem = "passageFailed"
        case .subagentFailed(let subtask):
            self.problem = "subagentFailed"
            self.subtask = subtask.rawValue
        case .executionFailed(let message):
            self.problem = "executionFailed"
            self.message = message
        case .interrupted:
            self.problem = "interrupted"
        }
    }

    var pendency: Pendency? {
        pendencyKind.map { Pendency(id: PendencyID(rawValue: id), kind: $0) }
    }

    private var pendencyKind: Pendency.Kind? {
        switch kind {
        case "decision": decision.flatMap { Self.decisions[$0] }.map { .decision($0) }
        case "stageFinished": .stageFinished
        case "returned": passage.flatMap(Passage.init).map { .returned($0) }
        case "chainLimitReached": chainLimit
        case "problem": storedProblem.map { .problem($0) }
        default: nil
        }
    }

    private var chainLimit: Pendency.Kind? {
        guard let destination, let passage = passage.flatMap(Passage.init) else { return nil }
        return .chainLimitReached(destination: StageID(rawValue: destination), passage: passage)
    }

    private var storedProblem: Problem? {
        switch problem {
        case "moveRefused": refusal.flatMap { Self.refusals[$0] }.map { .moveRefused($0) }
        case "passageFailed": .passageFailed
        case "subagentFailed": subtask.map { .subagentFailed(SubtaskID(rawValue: $0)) }
        case "executionFailed": message.map { .executionFailed($0) }
        case "interrupted": .interrupted
        default: nil
        }
    }
}

private struct StoredMovement: Codable {
    let from: UUID
    let to: UUID
    let agent: String?
    let at: Double
    let passage: String?

    init(_ movement: Movement) {
        from = movement.from.rawValue
        to = movement.to.rawValue
        if case .agent(let id) = movement.author { agent = id.rawValue } else { agent = nil }
        at = movement.at.timeIntervalSince1970
        passage = movement.passage?.text
    }

    var movement: Movement? {
        var kept: Passage?
        if let passage {
            guard let valid = Passage(passage) else { return nil }
            kept = valid
        }
        return Movement(from: StageID(rawValue: from), to: StageID(rawValue: to),
                        author: agent.map { .agent(AgentID($0)) } ?? .user,
                        at: Date(timeIntervalSince1970: at), passage: kept)
    }
}
