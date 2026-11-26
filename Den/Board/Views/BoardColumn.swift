import SwiftUI

struct BoardColumn: View {
    static let width: CGFloat = 280

    let column: ColumnDisplay
    let selectedTaskID: UUID?
    let select: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnHeader(name: column.name, taskCount: column.taskCount, isFinal: column.isFinal)
            if column.cards.isEmpty {
                Text("Nenhuma task")
                    .font(.system(size: Theme.font12))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, Theme.space10)
                    .padding(.top, Theme.space4)
                Spacer(minLength: 0)
            } else {
                cards
            }
        }
        .frame(width: Self.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: Theme.radius12, style: .continuous))
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: Theme.space8) {
                    ForEach(column.cards) { card in
                        TaskCard(card: card, isSelected: card.id == selectedTaskID)
                            .contentShape(.rect)
                            .onTapGesture { select(card.id) }
                            .accessibilityAddTraits(.isButton)
                            .id(card.id)
                    }
                }
                .padding(.horizontal, Theme.space8)
                .padding(.bottom, Theme.space8)
            }
            .scrollIndicators(.never)
            .onChange(of: selectedTaskID) { _, id in
                guard let id, column.cards.contains(where: { $0.id == id }) else { return }
                withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id) }
            }
        }
    }
}

#Preview("Com tasks") {
    BoardColumn(column: ColumnDisplay(id: UUID(), name: "Em andamento", isFinal: false, cards: [
        CardDisplay(id: UUID(), key: nil, title: "Exportar relatório em PDF", status: .running,
                    subtasks: SubtaskCount(done: 1, total: 3)),
        CardDisplay(id: UUID(), key: nil, title: "Revisar a migração do banco", status: .needsMe,
                    subtasks: nil),
    ]), selectedTaskID: nil) { _ in }
        .frame(height: 480)
        .padding()
        .background(Theme.canvas)
}

#Preview("Vazia") {
    BoardColumn(column: ColumnDisplay(id: UUID(), name: "Pronto", isFinal: true, cards: []),
                selectedTaskID: nil) { _ in }
        .frame(height: 480)
        .padding()
        .background(Theme.canvas)
}
