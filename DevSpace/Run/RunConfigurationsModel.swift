import Foundation
import Observation

@MainActor
@Observable
final class RunConfigurationsModel {
    nonisolated enum NameProblem: Equatable {
        case empty
        case duplicate
    }

    private(set) var projects: [ProjectRoot: [RunConfiguration]]

    @ObservationIgnored private let store: RunConfigurationStore

    init(store: RunConfigurationStore) {
        self.store = store
        self.projects = store.load()
    }

    func root(for directory: URL) -> URL {
        let known = Set(projects.filter { !$0.value.isEmpty }.keys)
        return RunProjectLocator.root(for: directory, knownRoots: known)
    }

    func configurations(in root: URL) -> [RunConfiguration] {
        projects[ProjectRoot(root)] ?? []
    }

    func add(_ configuration: RunConfiguration, to root: URL) {
        projects[ProjectRoot(root), default: []].append(configuration)
        persist()
    }

    func update(_ configuration: RunConfiguration, in root: URL) {
        let key = ProjectRoot(root)
        guard let index = projects[key]?.firstIndex(where: { $0.id == configuration.id }) else { return }
        projects[key]?[index] = configuration
        persist()
    }

    func remove(_ id: UUID, from root: URL) {
        let key = ProjectRoot(root)
        var list = projects[key] ?? []
        list.removeAll { $0.id == id }
        for index in list.indices {
            if case .compound(let members) = list[index].kind {
                list[index].kind = .compound(members.filter { $0 != id })
            }
        }
        projects[key] = list.isEmpty ? nil : list
        persist()
    }

    func nameProblem(for name: String, excluding id: UUID?, in root: URL) -> NameProblem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        let clash = configurations(in: root).contains {
            $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return clash ? .duplicate : nil
    }

    private func persist() {
        do {
            try store.save(projects)
        } catch {
            print("não consegui salvar as configurações de execução: \(error)")
        }
    }
}
