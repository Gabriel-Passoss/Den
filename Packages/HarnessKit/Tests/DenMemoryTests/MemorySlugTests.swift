import Testing
import Foundation
import DenMemory

@Test(arguments: [
    ("Commits seguem Conventional Commits", "commits-seguem-conventional-commits"),
    ("Área de Trabalho: ação & reação", "area-de-trabalho-acao-reacao"),
    ("  --Já começa-- com símbolos!!  ", "ja-comeca-com-simbolos"),
    ("snake_case e CamelCase", "snake-case-e-camelcase"),
    ("Swift 6.2 / macOS 26", "swift-6-2-macos-26"),
    ("🧨🧨🧨", "memoria"),
    ("", "memoria"),
])
func aTitleBecomesAFileName(title: String, slug: String) {
    #expect(MemorySlug.make(title) == slug)
}

@Test func aVeryLongTitleIsCutWithoutATrailingHyphen() {
    let slug = MemorySlug.make(String(repeating: "palavra ", count: 30))

    #expect(slug.count <= 60)
    #expect(slug.hasPrefix("palavra-palavra"))
    #expect(!slug.hasSuffix("-"))
}
