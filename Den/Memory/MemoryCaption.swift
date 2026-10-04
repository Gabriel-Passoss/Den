import Foundation
import DenMemory

extension MemoryModel.Status {
    var caption: String {
        switch self {
        case .idle: "A memória captura sozinha a cada poucas mensagens."
        case .capturing: "Capturando…"
        case .saved(1): "1 memória salva"
        case .saved(let count): "\(count) memórias salvas"
        case .nothingNew: "Nada novo para guardar"
        case .failed(let reason): reason
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension MemoryLayer {
    var title: String {
        switch self {
        case .project: "Projeto"
        case .user: "Usuário"
        }
    }

    var emptyExplanation: String {
        switch self {
        case .project: "Convenções, decisões e regras deste repositório aparecem aqui conforme a conversa avança."
        case .user: "Seu estilo, suas regras e seus processos aparecem aqui e valem em qualquer projeto."
        }
    }
}
