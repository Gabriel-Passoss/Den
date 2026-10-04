import SwiftUI
import AppKit

struct DenContextMenu: ViewModifier {
    let sections: [DenMenuSection]

    @State private var isOpen = false
    @State private var anchor = UnitPoint.center

    func body(content: Content) -> some View {
        content
            .overlay(SecondaryClickCatcher { point, size in
                guard size.width > 0, size.height > 0 else { return }
                anchor = UnitPoint(x: min(max(point.x / size.width, 0), 1),
                                   y: min(max(point.y / size.height, 0), 1))
                isOpen = true
            })
            .popover(isPresented: $isOpen, attachmentAnchor: .point(anchor), arrowEdge: .top) {
                DenMenuList(sections: sections) { isOpen = false }
                    .presentationBackground(Theme.raised)
                    .environment(\.colorScheme, .dark)
            }
    }
}

extension View {
    func denContextMenu(_ sections: [DenMenuSection]) -> some View {
        modifier(DenContextMenu(sections: sections))
    }
}

private struct SecondaryClickCatcher: NSViewRepresentable {
    var opened: (CGPoint, CGSize) -> Void

    func makeNSView(context: Context) -> CatchingView {
        let view = CatchingView()
        view.opened = opened
        return view
    }

    func updateNSView(_ view: CatchingView, context: Context) {
        view.opened = opened
    }

    final class CatchingView: NSView {
        var opened: ((CGPoint, CGSize) -> Void)?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isSecondary(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            report(event)
        }

        override func mouseDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.control) else {
                super.mouseDown(with: event)
                return
            }
            report(event)
        }

        static func isSecondary(_ event: NSEvent) -> Bool {
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                true
            case .leftMouseDown, .leftMouseUp:
                event.modifierFlags.contains(.control)
            default:
                false
            }
        }

        private func report(_ event: NSEvent) {
            opened?(convert(event.locationInWindow, from: nil), bounds.size)
        }
    }
}
