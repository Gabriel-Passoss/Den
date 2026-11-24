import Testing
import Foundation
@testable import SQLiteKit

private let busy = DatabaseError.sqlite(code: 5, message: "database is locked")

@Test func aBusyDatabaseIsTriedAgainUntilItAnswers() throws {
    var calls = 0

    try Database.waitingWhileBusy(patience: 5, pause: 0.001) {
        calls += 1
        if calls < 3 { throw busy }
    }

    #expect(calls == 3)
}

@Test func aDatabaseThatStaysBusyFailsOncePatienceRunsOut() {
    var calls = 0

    #expect(throws: busy) {
        try Database.waitingWhileBusy(patience: 0.05, pause: 0.01) {
            calls += 1
            throw busy
        }
    }
    #expect(calls > 1)
}

@Test func anyOtherFailureIsNotTriedAgain() {
    var calls = 0
    let broken = DatabaseError.sqlite(code: 1, message: "syntax error")

    #expect(throws: broken) {
        try Database.waitingWhileBusy(patience: 5, pause: 0.001) {
            calls += 1
            throw broken
        }
    }
    #expect(calls == 1)
}
