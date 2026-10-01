import Foundation
import HarnessCore

nonisolated struct PinnedHarness: Harness {
    let base: any Harness
    let executable: String

    var id: HarnessID { base.id }
    var displayName: String { base.displayName }

    func discover() async throws -> HarnessInstallation {
        HarnessInstallation(executable: executable, version: "0.0.0")
    }

    func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        base.capabilities(for: installation)
    }

    func knobs(for installation: HarnessInstallation,
               workingDirectory: URL) -> [HarnessKnob] {
        base.knobs(for: installation, workingDirectory: workingDirectory)
    }

    func makeSession(installation: HarnessInstallation, workingDirectory: URL,
                     settings: [String: String]) -> any HarnessSession {
        base.makeSession(installation: installation, workingDirectory: workingDirectory,
                         settings: settings)
    }

    func quickPromptArguments(for instruction: String) -> [String]? {
        base.quickPromptArguments(for: instruction)
    }
}

extension HarnessRegistry {
    func pinning(_ executables: [HarnessID: String]) -> HarnessRegistry {
        HarnessRegistry(harnesses: harnesses.map { harness in
            guard let path = executables[harness.id] else { return harness }
            return PinnedHarness(base: harness, executable: path)
        })
    }
}
