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
// O `raw` chega por parâmetro, e não reconstruído — mas hoje NENHUM chamador
// pode entregar um `raw` fiel para `entry(for:raw:)` (pedido). O
// `ControlChannel.consume` classifica o quadro, tem o `Data` cru na mão, e o
// descarta: devolve `.permissionRequest(request)` sem ele, e `PermissionRequest`
// (`HarnessCore/Permission.swift`) não tem campo `raw` para carregá-lo até
// aqui. O parâmetro existe para que esta função POSSA ser fiel assim que
// existir um chamador que a alimente — não porque um já exista. Ligar isso de
// verdade exige carregar o quadro cru através do canal de controle, e está
// registrado como pendência para a próxima etapa (ver
// `docs/superpowers/notes-2026-09-17-pendencias.md`).
//
// Para a DECISÃO o quadro de entrada nem existe: uma decisão nasce na UI do
// DevSpace, não numa linha do fio. O `raw` honesto para
// `entry(for:requestID:raw:)` é o `control_response` que NÓS escrevemos —
// `PermissionDecision.responseData(requestID:)` — ou `.null` quando esse
// payload não está à mão no ponto de chamada.
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
