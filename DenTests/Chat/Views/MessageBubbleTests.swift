import Testing
import Foundation
@testable import Den

@Test func shortTextPassesThroughUntouched() {
    #expect(MessageBubble.clipped("short", limit: 10) == "short")
    #expect(MessageBubble.clipped("0123456789", limit: 10) == "0123456789")
}

@Test func longTextIsCutAndAnnounced() {
    let text = String(repeating: "a", count: 25)
    let clipped = MessageBubble.clipped(text, limit: 10)
    #expect(clipped == String(repeating: "a", count: 10)
            + "\n⋯ +15 caracteres não exibidos")
}

@Test func textThatFitsInCharactersIsNeverAnnounced() {
    let accented = String(repeating: "á", count: 5)
    #expect(accented.utf8.count == 10)
    #expect(MessageBubble.clipped(accented, limit: 8) == accented)
}
