import Foundation
import HarnessCore

public struct OpenCodeHarness: Harness {
    public init() {}

    public var id: HarnessID { .openCode }
    public var displayName: String { "OpenCode" }

    public func discover() async throws -> HarnessInstallation {
        try await OpenCodeDiscovery().discover()
    }

    /// Medido contra o `opencode acp` 1.18.31, não suposto: `session/cancel`
    /// devolve `stopReason: "cancelled"`, `session/load` reproduz o histórico,
    /// e `session/set_config_option` troca modelo em sessão viva — este CLI faz
    /// o que o Claude Code não faz.
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

    /// Os botões do OpenCode só existem depois que uma sessão abre — é o
    /// `session/new` que devolve a lista de modelos. Antes disso não há o que
    /// oferecer, e inventar seria mentir.
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
