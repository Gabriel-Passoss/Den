import Foundation

public struct HarnessInstallation: Equatable, Sendable {

    public let executable: String
    public let version: String

    public init(executable: String, version: String) {
        self.executable = executable
        self.version = version
    }
}
