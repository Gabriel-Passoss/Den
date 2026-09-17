import HarnessCore

public extension HarnessID {
    /// O id deste harness. Mora aqui, e não em `HarnessCore`, porque o conjunto
    /// é aberto justamente para que o núcleo não precise conhecer harness
    /// nenhum — cada adaptador declara o seu (spec §7.1).
    static let claudeCode = HarnessID(rawValue: "claude-code")
}
