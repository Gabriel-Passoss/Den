import Foundation
import HarnessCore

extension CockpitModel {
    struct PendingAttachment: Identifiable, Equatable {
        let id = UUID()
        let data: Data
        let mediaType: String
        var name: String?

        var isImage: Bool { mediaType.hasPrefix("image/") }
    }
}
