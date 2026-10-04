import Testing
import SwiftUI
@testable import Den

@Test func aMenuWithoutASingleIconReservesNoIconColumn() {
    let sections = [DenMenuSection(items: [
        DenMenuItem(id: "a", title: "A"),
        DenMenuItem(id: "b", title: "B"),
    ])]

    #expect(DenMenuSection.showsIcons(in: sections) == false)
}

@Test func oneIconAnywhereReservesTheColumnForEveryRow() {
    let sections = [
        DenMenuSection(id: "plain", items: [DenMenuItem(id: "a", title: "A")]),
        DenMenuSection(id: "iconed", items: [
            DenMenuItem(id: "b", title: "B", icon: .symbol("hammer", Theme.added)),
        ]),
    ]

    #expect(DenMenuSection.showsIcons(in: sections))
}

@Test func anItemIsALeafUntilItIsGivenChildren() {
    let leaf = DenMenuItem(id: "leaf", title: "Nova pasta")
    let parent = DenMenuItem(id: "parent", title: "Nova sessão com",
                             children: [DenMenuSection(items: [leaf])])

    #expect(leaf.children.isEmpty)
    #expect(parent.children.flatMap(\.items).map(\.id) == ["leaf"])
}

@Test func anItemIsOnlyDestructiveWhenItSaysSo() {
    let plain = DenMenuItem(id: "rename", title: "Renomear")
    let destructive = DenMenuItem(id: "delete", title: "Apagar sessão…", isDestructive: true)

    #expect(plain.isDestructive == false)
    #expect(destructive.isDestructive)
}

@Test func aDangerousActionSitsInItsOwnSectionSoItGetsASeparator() {
    let sections = [
        DenMenuSection(id: "edit", items: [DenMenuItem(id: "rename", title: "Renomear")]),
        DenMenuSection(id: "danger", items: [
            DenMenuItem(id: "delete", title: "Apagar sessão…", isDestructive: true),
        ]),
    ]

    #expect(sections.allSatisfy { $0.header == nil })
    #expect(sections.last?.items.allSatisfy(\.isDestructive) == true)
}
