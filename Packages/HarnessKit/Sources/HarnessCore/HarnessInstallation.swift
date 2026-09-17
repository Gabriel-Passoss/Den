import Foundation

/// Onde um harness está instalado e em que versão.
public struct HarnessInstallation: Equatable, Sendable {
    /// Caminho lógico, nunca o alvo resolvido do symlink: o Homebrew aponta
    /// para um diretório versionado que muda a cada atualização (spec §4.4).
    public let executable: String
    public let version: String

    public init(executable: String, version: String) {
        self.executable = executable
        self.version = version
    }
}
