import SwiftUI

struct BoardView: View {
    let model: BoardModel
    @Environment(\.chrome) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                TopBar(leadingInset: chrome.leadingInset + Theme.space12) {
                    SidebarToggle()
                    if case .board(let name, _) = model.content {
                        Text(name)
                            .font(.system(size: Theme.font13, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    if case .board(_, let display) = model.content {
                        counter(display.needsMeCount, proxy: proxy)
                    }
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .navigationTitle("")
        .task { model.load() }
    }

    private func counter(_ count: Int, proxy: ScrollViewProxy) -> some View {
        Button {
            guard let place = model.selectNextNeedingMe() else { return }
            withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(place.column) }
        } label: {
            NeedsMeCounter(count: count)
        }
        .buttonStyle(.plain)
        .help("Ir para a próxima task que precisa de você")
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            Color.clear
        case .noProject:
            BoardEmptyState(symbol: "folder",
                            title: "Nenhum projeto",
                            message: "Cadastre um projeto para montar o board dele.")
        case .failed:
            BoardEmptyState(symbol: "exclamationmark.triangle",
                            title: "Não consegui abrir o board",
                            message: "O banco do Den não pôde ser lido.")
        case .board(_, let display) where display.columns.isEmpty:
            BoardEmptyState(symbol: "rectangle.split.3x1",
                            title: "Este board ainda não tem etapas",
                            message: "Crie a primeira etapa nas configurações do projeto para montar o seu fluxo.")
        case .board(_, let display):
            columns(display.columns)
        }
    }

    private func columns(_ columns: [ColumnDisplay]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Theme.space12) {
                ForEach(columns) { column in
                    BoardColumn(column: column, selectedTaskID: model.selectedTaskID, select: model.select)
                        .id(column.id)
                }
            }
            .padding(Theme.space16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
    }
}

private struct BoardEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.space12) {
            Image(systemName: symbol)
                .font(.system(size: Theme.font24, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            VStack(spacing: Theme.space4) {
                Text(title)
                    .font(.system(size: Theme.font14, weight: .semibold))
                Text(message)
                    .font(.system(size: Theme.font13))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 320)
    }
}
