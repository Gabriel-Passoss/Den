/// Qual harness hospeda um trecho de conversa.
///
/// É um conjunto ABERTO, não um enum: um enum fechado obrigaria a editar
/// `HarnessCore` para acrescentar um harness, que é exatamente o acoplamento
/// que a spec §7.1 existe para impedir. Cada adaptador declara o próprio id.
public struct HarnessID: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let claudeCode = HarnessID(rawValue: "claude-code")
}
