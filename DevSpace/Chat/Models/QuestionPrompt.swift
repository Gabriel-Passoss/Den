import Foundation
import HarnessCore

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

extension QuestionPrompt {
    init?(from request: PermissionRequest) {
        guard let items = request.input["questions"]?.arrayValue else { return nil }
        
        let questions = items.compactMap { item -> Question? in
            guard let text = item["question"]?.stringValue,
                  let options = item["options"]?.arrayValue else { return nil }
            
            let parsed = options.compactMap { option -> Option? in
                guard let label = option["label"]?.stringValue else { return nil }
                return Option(label: label,
                              detail: option["description"]?.stringValue ?? "")
            }
            
            guard !parsed.isEmpty else { return nil }
            return Question(text: text,
                            header: item["header"]?.stringValue ?? "",
                            multiSelect: item["multiSelect"]?.boolValue ?? false,
                            options: parsed)
        }
        
        guard !questions.isEmpty else { return nil }
        self.init(id: request.id, questions: questions, request: request)
    }
}
