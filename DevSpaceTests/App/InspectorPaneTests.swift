import Testing
import Foundation
@testable import DevSpace

@Test func aLegacyOpenInspectorBecomesTheChangesPane() {
    withTemporaryDefaults { defaults in
        defaults.set(true, forKey: "DevSpace.gitInspector")
        InspectorPane.migrateLegacy(in: defaults)
        #expect(defaults.string(forKey: InspectorPane.storageKey) == "changes")
        #expect(defaults.object(forKey: "DevSpace.gitInspector") == nil)
    }
}

@Test func aLegacyClosedInspectorLeavesThePaneClosed() {
    withTemporaryDefaults { defaults in
        defaults.set(false, forKey: "DevSpace.gitInspector")
        InspectorPane.migrateLegacy(in: defaults)
        #expect(defaults.string(forKey: InspectorPane.storageKey) == nil)
        #expect(defaults.object(forKey: "DevSpace.gitInspector") == nil)
    }
}

@Test func anExistingPaneIsNotOverwritten() {
    withTemporaryDefaults { defaults in
        defaults.set("run", forKey: InspectorPane.storageKey)
        defaults.set(true, forKey: "DevSpace.gitInspector")
        InspectorPane.migrateLegacy(in: defaults)
        #expect(defaults.string(forKey: InspectorPane.storageKey) == "run")
    }
}
