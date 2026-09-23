import Foundation
import HarnessCore

extension CockpitModel {
    nonisolated static func displayName(for modelID: String) -> String {
        var words = modelID.split(separator: "-").map(String.init)
        if words.first?.lowercased() == "claude" { words.removeFirst() }
        if let last = words.last, last.count == 8, last.allSatisfy(\.isNumber) {
            words.removeLast()
        }
        var parts: [String] = []
        for word in words {
            if word.allSatisfy(\.isNumber), let previous = parts.last,
               previous.last?.isNumber == true {
                parts[parts.count - 1] = previous + "." + word
            } else {
                parts.append(word.allSatisfy(\.isNumber) ? word : word.capitalized)
            }
        }
        return parts.joined(separator: " ")
    }
}
