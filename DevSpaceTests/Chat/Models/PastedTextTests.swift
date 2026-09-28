import Testing
import Foundation
@testable import DevSpace

@Test func headlineIsTheFirstLineWithContent() {
    let paste = PastedText(text: "\n\n   \n  func main() {\n    run()\n}\n")
    #expect(paste.headline == "func main() {")
}

@Test func lineCountIsWorkedOutOnceUpFront() {
    let paste = PastedText(text: "a\nb\nc\n")
    #expect(paste.lineCount == 3)
}
