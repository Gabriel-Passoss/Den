import Foundation

func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
