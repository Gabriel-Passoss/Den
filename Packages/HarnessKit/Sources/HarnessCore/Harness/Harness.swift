import Foundation

public protocol Harness: Sendable {

    var id: HarnessID { get }

    var displayName: String { get }

    func discover() async throws -> HarnessInstallation

    func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities

    // periphery:ignore:parameters installation
    func knobs(for installation: HarnessInstallation,
               workingDirectory: URL) -> [HarnessKnob]

    func makeSession(installation: HarnessInstallation,
                     workingDirectory: URL,
                     settings: [String: String]) -> any HarnessSession

    func quickPromptArguments(for instruction: String) -> [String]?
}

public extension Harness {
    func quickPromptArguments(for instruction: String) -> [String]? { nil }
}
