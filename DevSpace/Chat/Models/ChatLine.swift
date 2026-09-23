import Foundation
import HarnessCore

extension CockpitModel {
    struct Line: Identifiable {
        enum Role {
            case user, assistant, thinking, tool, toolResult, notice, unknown
            case compaction, digest

            var isStep: Bool {
                switch self {
                case .thinking, .tool, .toolResult, .notice, .unknown: true
                case .user, .assistant, .compaction, .digest: false
                }
            }
        }
        let id: UUID
        let role: Role
        let text: String
        var images: [Data] = []
        var files: [String] = []

        let timestamp: Date

        var verb: CanonicalTool?

        var title: String?
    }
}
