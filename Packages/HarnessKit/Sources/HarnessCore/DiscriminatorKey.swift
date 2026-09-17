/// Chave de codificação dinâmica: aceita qualquer string.
///
/// Um enum aberto — um que degrada um caso desconhecido em vez de estourar —
/// precisa ler e reescrever um discriminador cujo nome não existe em tempo de
/// compilação. Uma `CodingKeys` nomeada não serve: ela só sabe os nomes que
/// ESTA versão conhece, e o caso de fuga existe justamente para os outros.
///
/// Interno e compartilhado porque já são dois os enums abertos do transcript
/// (`TranscriptEntry.Kind` e `Handoff`), e os dois precisam exatamente disto.
struct DiscriminatorKey: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}
