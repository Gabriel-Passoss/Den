import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

@Test func aTextOnlyTurnKeepsTheStringContentWire() {
    let line = ClaudeSession.userTurn(text: "oi", images: [])
    #expect(line["message"]?["content"]?.stringValue == "oi")
}

@Test func aTurnWithImagesBecomesContentBlocks() {
    let data = Data([0x89, 0x50, 0x4E, 0x47])
    let line = ClaudeSession.userTurn(
        text: "o que é isto?",
        images: [ImageAttachment(mediaType: "image/png", data: data)]
    )
    let blocks = line["message"]?["content"]?.arrayValue
    #expect(blocks?.count == 2)
    #expect(blocks?[0]["type"]?.stringValue == "image")
    #expect(blocks?[0]["source"]?["type"]?.stringValue == "base64")
    #expect(blocks?[0]["source"]?["media_type"]?.stringValue == "image/png")
    #expect(blocks?[0]["source"]?["data"]?.stringValue == data.base64EncodedString())
    #expect(blocks?[1]["type"]?.stringValue == "text")
    #expect(blocks?[1]["text"]?.stringValue == "o que é isto?")
}

@Test func anImageOnlyTurnHasNoEmptyTextBlock() {
    let line = ClaudeSession.userTurn(
        text: "",
        images: [ImageAttachment(mediaType: "image/png", data: Data([1]))]
    )
    let blocks = line["message"]?["content"]?.arrayValue
    #expect(blocks?.count == 1)
    #expect(blocks?[0]["type"]?.stringValue == "image")
}
