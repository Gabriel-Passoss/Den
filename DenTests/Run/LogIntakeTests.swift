import Testing
import Foundation
@testable import Den

private final class Received {
    var events: [ANSIParser.Event] = []
    var batches = 0
}

@Test func intakeDeliversEverythingBeforeTheCompletion() async {
    let received = Received()
    await withCheckedContinuation { continuation in
        let intake = LogIntake(interval: .zero) { received.events += $0 }
        intake.receive(Data("a\n".utf8))
        intake.receive(Data("\u{1B}[31mb".utf8))
        intake.finish { continuation.resume() }
    }
    #expect(received.events == [
        .text("a", LogStyle()), .newline,
        .text("b", LogStyle(foreground: .palette(1))),
    ])
}

@Test func intakeBatchesChunksThatArriveTogether() async {
    let received = Received()
    await withCheckedContinuation { continuation in
        let intake = LogIntake(interval: .milliseconds(200)) { _ in received.batches += 1 }
        for index in 0..<50 { intake.receive(Data("\(index)\n".utf8)) }
        intake.finish { continuation.resume() }
    }
    #expect(received.batches == 1)
}
