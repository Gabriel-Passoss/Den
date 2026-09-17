import Foundation
import HarnessCore

// As duas entradas da spec §4.2 que não vêm do stdout de conversa.
//
// O canal de controle (Etapa 3) já entrega um `PermissionRequest` neutro e a
// UI já devolve uma `PermissionDecision` neutra; o que falta é o passo de
// virar transcript, com o carimbo e o `raw` certos. É o mesmo ofício do resto
// do mapeador, e é aqui que mora o relógio injetado — por isso são métodos de
// instância.
//
// O `raw` chega por parâmetro em vez de ser reconstruído: só o chamador tem a
// linha original do fio, e a §4.2 exige um registro fiel, não uma
// reconstrução aproximada.
public extension ClaudeEventMapper {
    /// A entrada que registra que o harness pediu permissão.
    func entry(for request: PermissionRequest, raw: JSONValue) -> TranscriptEntry {
        TranscriptEntry(timestamp: now(), kind: .permissionRequest(request), raw: raw)
    }

    /// A entrada que registra o que se decidiu sobre um pedido.
    ///
    /// `requestID` é o `PermissionRequest.id` a que esta decisão responde — o
    /// par é o que permite ler o transcript e saber o que foi aprovado.
    func entry(for decision: PermissionDecision, requestID: String,
               raw: JSONValue) -> TranscriptEntry {
        TranscriptEntry(
            timestamp: now(),
            kind: .permissionDecision(requestID: requestID, decision),
            raw: raw
        )
    }
}
