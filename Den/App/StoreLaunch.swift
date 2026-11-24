import Foundation
import DenStore

nonisolated struct StoreLaunch {
    let repositories: Repositories
    let failure: String?

    static func open(_ file: URL) -> StoreLaunch {
        do {
            let opened = try DenStore.open(at: file)
            if let aside = opened.setAside {
                print("banco de dados ilegível posto de lado em \(aside.path)")
            }
            return StoreLaunch(repositories: opened.repositories, failure: nil)
        } catch {
            return StoreLaunch(repositories: emptyStore(), failure: message(for: error))
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case DenStoreError.newerSchema(let found, let supported):
            "Este banco de dados foi gravado por uma versão mais nova do Den (esquema \(found); "
                + "esta versão entende até o \(supported)). Abra-o com a versão mais nova. Nada foi alterado."
        case DenStoreError.unavailable(let reason):
            "Não consegui abrir o banco de dados do Den: \(reason)"
        default:
            "Não consegui abrir o banco de dados do Den: \(error.localizedDescription)"
        }
    }

    private static func emptyStore() -> Repositories {
        do {
            return try DenStore.inMemory()
        } catch {
            fatalError("o SQLite em memória não abriu: \(error)")
        }
    }
}
