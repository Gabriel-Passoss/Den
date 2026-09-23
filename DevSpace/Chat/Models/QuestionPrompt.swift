import Foundation
import HarnessCore

extension CockpitModel {
    struct QuestionPrompt: Identifiable {
        struct Option { let label: String; let detail: String }
        struct Question {
            let text: String
            let header: String
            let multiSelect: Bool
            let options: [Option]
        }
        let id: String
        let questions: [Question]
        let request: PermissionRequest
    }

    static func questionPrompt(from request: PermissionRequest) -> QuestionPrompt? {
        guard let items = request.input["questions"]?.arrayValue else { return nil }
        let questions = items.compactMap { item -> QuestionPrompt.Question? in
            guard let text = item["question"]?.stringValue,
                  let options = item["options"]?.arrayValue else { return nil }
            let parsed = options.compactMap { option -> QuestionPrompt.Option? in
                guard let label = option["label"]?.stringValue else { return nil }
                return QuestionPrompt.Option(
                    label: label, detail: option["description"]?.stringValue ?? "")
            }
            guard !parsed.isEmpty else { return nil }
            return QuestionPrompt.Question(
                text: text,
                header: item["header"]?.stringValue ?? "",
                multiSelect: item["multiSelect"]?.boolValue ?? false,
                options: parsed)
        }
        guard !questions.isEmpty else { return nil }
        return QuestionPrompt(id: request.id, questions: questions, request: request)
    }
}
