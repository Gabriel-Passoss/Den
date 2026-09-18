import SwiftUI
import HarnessCore
import ClaudeHarness

/// A marca do harness que hospeda um trecho de conversa.
///
/// A tradução `HarnessID` → arte e nome mora AQUI, num lugar só, e não espalhada
/// pelas views. Quando o Codex entrar, ele acrescenta uma linha nas duas funções
/// abaixo e aparece na sidebar sem que nenhuma view seja tocada — que é a
/// mesma disciplina da spec §7.1 um andar acima: o orquestrador conhece o
/// conjunto de harnesses, a tela não.
struct HarnessBadge: View {
    /// `nil` quando não se sabe qual harness — uma sessão em disco cujos
    /// metadados não listam nenhum, por exemplo. Melhor uma marca neutra que
    /// um palpite: chutar "Claude Code" numa sessão do Codex seria mentir na
    /// única linha que o usuário lê para se orientar.
    let harness: HarnessID?
    var size: CGFloat = 15

    var body: some View {
        Group {
            if let harness, let asset = Self.asset(for: harness) {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Um harness sem arte não fica sem marca: a inicial serve, e é
                // honesta sobre não sabermos desenhá-lo ainda.
                Text(harness.map { Self.name(for: $0).prefix(1) } ?? "?")
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }

    /// O nome do asset em `Assets.xcassets`, quando temos a arte.
    static func asset(for harness: HarnessID) -> String? {
        switch harness {
        case .claudeCode: "HarnessClaudeCode"
        default: nil
        }
    }

    /// Como o harness se chama para quem lê.
    static func name(for harness: HarnessID) -> String {
        switch harness {
        case .claudeCode: "Claude Code"
        default: harness.rawValue
        }
    }
}
