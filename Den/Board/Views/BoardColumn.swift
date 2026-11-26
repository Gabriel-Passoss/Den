import SwiftUI

struct BoardColumn: View {
    static let width: CGFloat = 280

    let column: ColumnDisplay
    let selectedTaskID: UUID?
    let select: (UUID) -> Void
    var destinations: [ColumnDisplay] = []
    var move: (UUID, UUID) -> Void = { _, _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

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
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius12, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: isTargeted ? 2 : 0)
        }
        .dropDestination(for: String.self) { items, _ in
            let cards = items.compactMap(UUID.init(uuidString:))
            cards.forEach { move($0, column.id) }
            return !cards.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    private var otherColumns: [ColumnDisplay] {
        destinations.filter { $0.id != column.id }
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
                            .draggable(card.id.uuidString) {
                                TaskCard(card: card, isDragging: true)
                                    .frame(width: Self.width - 2 * Theme.space8)
                            }
                            .contextMenu {
                                Menu("Mover para") {
                                    ForEach(otherColumns) { other in
                                        Button(other.name) { move(card.id, other.id) }
                                    }
                                }
                            }
                            .accessibilityActions {
                                ForEach(otherColumns) { other in
                                    Button("Mover para \(other.name)") { move(card.id, other.id) }
                                }
                            }
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
