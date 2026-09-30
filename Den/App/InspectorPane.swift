import Foundation

enum InspectorPane: String {
    case closed = ""
    case changes
    case run

    static let storageKey = "Den.inspector"
}
