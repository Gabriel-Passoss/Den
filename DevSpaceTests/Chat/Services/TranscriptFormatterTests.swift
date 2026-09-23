import Testing
import Foundation
import HarnessCore
@testable import DevSpace

@Test func unwrappedStripsCommandEnvelopes() {
    let wrapped = "<command-name>/compact</command-name>\n<command-args> agora </command-args>"
    #expect(TranscriptFormatter.unwrapped(wrapped) == "/compact\n agora")
    #expect(TranscriptFormatter.unwrapped("<local-command-stdout>saída</local-command-stdout>") == "saída")
    #expect(TranscriptFormatter.unwrapped("  sem envelope  ") == "sem envelope")
}

@Test func tokensAbbreviateThousands() {
    #expect(TranscriptFormatter.tokens(999) == "999")
    #expect(TranscriptFormatter.tokens(1_000) == "1k")
    #expect(TranscriptFormatter.tokens(1_499) == "1k")
    #expect(TranscriptFormatter.tokens(1_500) == "2k")
    #expect(TranscriptFormatter.tokens(155_000) == "155k")
}

@Test func elapsedSwitchesToMinutesAtSixty() {
    #expect(TranscriptFormatter.elapsed(45) == "45s")
    #expect(TranscriptFormatter.elapsed(59.4) == "59s")
    #expect(TranscriptFormatter.elapsed(60) == "1min 0s")
    #expect(TranscriptFormatter.elapsed(75) == "1min 15s")
}

@Test func headlineDescribesTheCompaction() {
    let full = ContextCompaction(trigger: .manual, tokensBefore: 155_000,
                                 tokensAfter: 8_000, duration: 75)
    #expect(TranscriptFormatter.headline(of: full)
            == "Conversa compactada · 155k → 8k tokens · 1min 15s")

    let bare = ContextCompaction(trigger: .automatic, tokensBefore: 0,
                                 tokensAfter: 0, duration: 0)
    #expect(TranscriptFormatter.headline(of: bare) == "Conversa compactada")
}

@Test func summaryPrefersTheMostSpecificField() {
    func call(_ input: JSONValue) -> ToolCall {
        ToolCall(id: "1", rawName: "Tool", canonical: nil, input: input)
    }
    #expect(TranscriptFormatter.summary(of: call(.object(["command": .string("ls -la")]))) == "ls -la")
    #expect(TranscriptFormatter.summary(of: call(.object(["file_path": .string("/a/b/C.swift")]))) == "C.swift")
    #expect(TranscriptFormatter.summary(of: call(.object(["pattern": .string("TODO")]))) == "TODO")
    #expect(TranscriptFormatter.summary(of: call(.object(["url": .string("https://x.dev")]))) == "https://x.dev")
    #expect(TranscriptFormatter.summary(of: call(.object(["x": .int(1)]))) == "x=1")
}

@Test func oneLineFlattensSortsAndTruncates() {
    #expect(TranscriptFormatter.oneLine(.null) == "—")
    #expect(TranscriptFormatter.oneLine(.object(["b": .int(2), "a": .string("x")])) == "a=x b=2")
    #expect(TranscriptFormatter.oneLine(.array([.int(1), .bool(true)])) == "1, true")
    #expect(TranscriptFormatter.oneLine(.string("um\ndois")) == "um dois")

    let long = TranscriptFormatter.oneLine(.string(String(repeating: "x", count: 250)))
    #expect(long.count == 201)
    #expect(long.hasSuffix("…"))
}
