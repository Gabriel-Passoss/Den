import Testing
@testable import Den

@Test func aRestoredPaneIsTheOneShown() {
    #expect(InspectorPane.run.shown(after: .changes) == .run)
    #expect(InspectorPane.changes.shown(after: .run) == .changes)
    #expect(InspectorPane.closed.shown(after: .run) == .run)
}
