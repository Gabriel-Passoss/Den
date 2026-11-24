import SwiftUI
import AppKit

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var focusRequested: Bool
    var accessibilityPlaceholder: String
    var ghost = ""
    var onSubmit: () -> Void
    var onPaste: (String) -> Bool
    var onAcceptGhost: () -> Void = {}
    var onDismissGhost: () -> Void = {}

    static let font = NSFont.systemFont(ofSize: 13)
    static let maxLines = 6
    static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
    static let ghostTrailing: CGFloat = 30
    static let ghostMaxLines = 3

    static func height(of text: String, width: CGFloat) -> CGFloat {
        let cap = lineHeight * CGFloat(maxLines)
        guard text.utf8.count < 5_000 else { return cap }
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        return min(max(ceil(used / lineHeight) * lineHeight, lineHeight), cap)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: .greatestFiniteMagnitude)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.setAccessibilityPlaceholderValue(accessibilityPlaceholder)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? PromptTextView else { return }
        textView.onPaste = onPaste
        if textView.string != text {
            textView.string = text
            context.coordinator.undo.removeAllActions()
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            textView.scrollToEndOfDocument(nil)
        }
        if focusRequested {
            textView.window?.makeFirstResponder(textView)
            DispatchQueue.main.async { focusRequested = false }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        guard text.isEmpty, !ghost.isEmpty else {
            return CGSize(width: width, height: Self.height(of: text, width: width))
        }
        let measured = Self.height(of: ghost, width: width - Self.ghostTrailing)
        return CGSize(width: width,
                      height: min(measured, Self.lineHeight * CGFloat(Self.ghostMaxLines)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        let undo = UndoManager()

        init(_ parent: ComposerTextView) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                guard NSApp.currentEvent?.modifierFlags.contains(.shift) != true else { return false }
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.moveRight(_:)):
                guard textView.string.isEmpty, !parent.ghost.isEmpty else { return false }
                parent.onAcceptGhost()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if !parent.ghost.isEmpty { parent.onDismissGhost() }
                return true
            default:
                return false
            }
        }
    }
}

final class PromptTextView: NSTextView {
    var onPaste: (String) -> Bool = { _ in false }

    func capture(from pasteboard: NSPasteboard) -> Bool {
        guard let text = pasteboard.string(forType: .string) else { return false }
        return onPaste(text)
    }

    override func paste(_ sender: Any?) {
        if !capture(from: .general) { super.paste(sender) }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if !capture(from: .general) { super.pasteAsPlainText(sender) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.firstResponder === window else { return }
        window.makeFirstResponder(self)
    }
}
