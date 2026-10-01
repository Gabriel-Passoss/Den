import Foundation

enum ContextFormat {

    static func tokens(_ value: Int) -> String {
        switch value {
        case ..<1_000: String(value)
        case ..<1_000_000: decimal(Double(value) / 1_000) + "k"
        default: decimal(Double(value) / 1_000_000) + "M"
        }
    }

    static func percent(_ fraction: Double) -> String {
        decimal(fraction * 100) + "%"
    }

    static func summary(used: Int, window: Int) -> String {
        let share = window > 0 ? Double(used) / Double(window) : 0
        return "\(tokens(used)) / \(tokens(window)) (\(percent(share)))"
    }

    private static let locale = Locale(identifier: "pt_BR")

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
    }
}
