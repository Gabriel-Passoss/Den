import Testing
import Foundation
import HarnessCore

@Test func aMappedOutputCarriesTheTwoStreamsSeparately() {
    let entry = TranscriptEntry(
        timestamp: Date(timeIntervalSince1970: 0),
        kind: .assistantText("pronto"),
        raw: .object(["type": .string("text")])
    )
    let output = MappedOutput(events: [.turnStarted], entries: [entry])

    #expect(output.events == [.turnStarted])
    #expect(output.entries.count == 1)
    #expect(output.entries[0].kind == .assistantText("pronto"))
}

@Test func anEmptyOutputCarriesNothing() {
    #expect(MappedOutput.empty.events.isEmpty)
    #expect(MappedOutput.empty.entries.isEmpty)
}

@Test func deltasAreDistinguishedByBlockIndex() {
    let a = SessionEvent.textDelta(blockIndex: 0, text: "hi")
    let b = SessionEvent.textDelta(blockIndex: 1, text: "hi")
    #expect(a != b)
}
