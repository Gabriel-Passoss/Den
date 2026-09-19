import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

@Test func aTextOnlyTurnKeepsTheStringContentWire() {
    let line = ClaudeSession.userTurn(text: "oi", attachments: [])
    #expect(line["message"]?["content"]?.stringValue == "oi")
}

@Test func aTurnWithImagesBecomesContentBlocks() {
    let data = Data([0x89, 0x50, 0x4E, 0x47])
    let line = ClaudeSession.userTurn(
        text: "o que é isto?",
        attachments: [MediaAttachment(mediaType: "image/png", data: data)]
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

@Test func aPDFBecomesADocumentBlock() {
    let data = Data([0x25, 0x50, 0x44, 0x46])
    let line = ClaudeSession.userTurn(
        text: "resuma este arquivo",
        attachments: [MediaAttachment(mediaType: "application/pdf", data: data)]
    )
    let blocks = line["message"]?["content"]?.arrayValue
    #expect(blocks?.count == 2)
    #expect(blocks?[0]["type"]?.stringValue == "document")
    #expect(blocks?[0]["source"]?["type"]?.stringValue == "base64")
    #expect(blocks?[0]["source"]?["media_type"]?.stringValue == "application/pdf")
    #expect(blocks?[0]["source"]?["data"]?.stringValue == data.base64EncodedString())
}

@Test func anImageOnlyTurnHasNoEmptyTextBlock() {
    let line = ClaudeSession.userTurn(
        text: "",
        attachments: [MediaAttachment(mediaType: "image/png", data: Data([1]))]
    )
    let blocks = line["message"]?["content"]?.arrayValue
    #expect(blocks?.count == 1)
    #expect(blocks?[0]["type"]?.stringValue == "image")
}
