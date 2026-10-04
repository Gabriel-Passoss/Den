import SwiftUI

enum DenMenuIcon {
    case symbol(String, Color)
    case image(Image)
}

struct DenMenuItem: Identifiable {
    let id: String
    var title: String
    var icon: DenMenuIcon?
    var isSelected: Bool
    var isEnabled: Bool
    var isDestructive: Bool
    var children: [DenMenuSection]
    var action: () -> Void

    init(id: String,
         title: String,
         icon: DenMenuIcon? = nil,
         isSelected: Bool = false,
         isEnabled: Bool = true,
         isDestructive: Bool = false,
         children: [DenMenuSection] = [],
         action: @escaping () -> Void = {}) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.children = children
        self.action = action
    }
}

struct DenMenuSection: Identifiable {
    let id: String
    var header: String?
    var items: [DenMenuItem]

    init(id: String = "main", header: String? = nil, items: [DenMenuItem]) {
        self.id = id
        self.header = header
        self.items = items
    }

    static func showsIcons(in sections: [DenMenuSection]) -> Bool {
        sections.contains { $0.items.contains { $0.icon != nil } }
    }
}
