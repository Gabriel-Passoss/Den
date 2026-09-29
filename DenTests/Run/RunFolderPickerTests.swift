import Testing
import AppKit
import SwiftUI
@testable import Den

private func textFields(in view: NSView) -> [NSTextField] {
    var found: [NSTextField] = []
    if let field = view as? NSTextField, field.isEditable { found.append(field) }
    for subview in view.subviews { found += textFields(in: subview) }
    return found
}

private struct PickerInForm: View {
    @State var selection = ""
    var body: some View {
        Form {
            Section {
                RunFolderPicker(root: FileManager.default.temporaryDirectory, selection: $selection)
            } header: {
                Text("Pasta")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 400)
    }
}

@Test func theSearchFieldSpansThePickerInsideAGroupedForm() throws {
    let hosting = NSHostingView(rootView: PickerInForm())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()

    let field = try #require(textFields(in: hosting).first)
    let frame = field.convert(field.bounds, to: nil)
    #expect(field.placeholderString == "Buscar pasta")
    #expect(frame.minX < 120)
    #expect(frame.width > 300)
}
