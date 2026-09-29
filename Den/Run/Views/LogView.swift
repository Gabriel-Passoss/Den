import AppKit
import SwiftUI

struct LogView: NSViewRepresentable {
    let instance: RunInstance
    let followRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = true
            text.drawsBackground = false
            text.usesFindBar = true
            text.isIncrementalSearchingEnabled = true
            text.textContainerInset = NSSize(width: 6, height: 6)
            text.font = NSFont.monospacedSystemFont(ofSize: LogRenderer.fontSize, weight: .regular)
            text.setAccessibilityLabel("Log")
            context.coordinator.textView = text
        }
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.show(instance)
        context.coordinator.follow(followRequest)
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        weak var textView: NSTextView?
        private var document: LogDocument?
        private weak var instance: RunInstance?
        private var token: UUID?
        private var lastFollowRequest = 0

        func show(_ instance: RunInstance) {
            guard instance !== self.instance, let textView, let storage = textView.textStorage else { return }
            detach()
            self.instance = instance
            let document = LogDocument(storage: storage)
            document.reload(instance.log.lines)
            self.document = document
            token = instance.observeLog { [weak self] changes in self?.apply(changes) }
            scrollToEnd()
        }

        func follow(_ request: Int) {
            guard request != lastFollowRequest else { return }
            lastFollowRequest = request
            scrollToEnd()
        }

        func detach() {
            if let token { instance?.stopObserving(token) }
            token = nil
            instance = nil
            document = nil
        }

        private func apply(_ changes: [LogChange]) {
            let following = isAtEnd
            document?.apply(changes)
            if following { scrollToEnd() }
        }

        private var isAtEnd: Bool {
            guard let textView, let clip = textView.enclosingScrollView?.contentView else { return true }
            return clip.bounds.maxY >= textView.frame.height - 24
        }

        private func scrollToEnd() {
            textView?.scrollToEndOfDocument(nil)
        }
    }
}
