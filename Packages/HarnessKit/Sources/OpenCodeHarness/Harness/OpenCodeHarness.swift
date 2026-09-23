import Foundation
import HarnessCore

public struct OpenCodeHarness: Harness {
    public init() {}

    public var id: HarnessID { .openCode }
    public var displayName: String { "OpenCode" }

    public func discover() async throws -> HarnessInstallation {
        try await OpenCodeDiscovery().discover()
    }

    public func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        HarnessCapabilities(
            routesPermissionRequests: true,
            canInterrupt: true,
            canSetPermissionMode: true,
            canSetModelInSession: true,
            canResumeSession: true,
            canForkSession: true
        )
    }

    public func knobs(for installation: HarnessInstallation,
                      workingDirectory: URL) -> [HarnessKnob] {
        []
    }

    public func makeSession(installation: HarnessInstallation,
                            workingDirectory: URL,
                            settings: [String: String]) -> any HarnessSession {
        OpenCodeSession(installation: installation,
                        workingDirectory: workingDirectory,
                        settings: settings)
    }
}
