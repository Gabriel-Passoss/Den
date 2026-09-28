import SwiftUI
import AppKit
import Observation
import HarnessCore

struct ZoomedImage: Identifiable, Equatable {
    let id = UUID()
    let data: Data
}

@Observable final class ChatKeyMonitor {
    var escArmed = false
    var composerFocused = false

    private var monitor: Any?
    private var escDisarm: Task<Void, Never>?

    func install(chat: ChatModel, slash: SlashController,
                 mentions: MentionController, zoomed: Binding<ZoomedImage?>,
                 stickToBottom: @escaping () -> Void) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 36, event.modifierFlags.contains(.shift),
               let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
               editor.isFieldEditor {
                editor.insertNewlineIgnoringFieldEditor(nil)
                return nil
            }
            let slashMatches = slash.matches(prompt: chat.prompt,
                                                  catalog: chat.catalog)
            if !slashMatches.isEmpty {
                let selected = min(slash.selection, slashMatches.count - 1)
                switch event.keyCode {
                case 125:
                    slash.selection = min(selected + 1, slashMatches.count - 1)
                    return nil
                case 126:
                    slash.selection = max(selected - 1, 0)
                    return nil
                case 36, 48:
                    if slash.run(slashMatches[selected], in: chat) {
                        stickToBottom()
                    }
                    return nil
                case 53:
                    if slash.group != nil {
                        slash.leaveGroup(in: chat)
                    } else {
                        slash.dismissed = true
                    }
                    return nil
                case 51 where slash.group != nil && chat.prompt == "/":
                    slash.leaveGroup(in: chat)
                    return nil
                default:
                    break
                }
            }
            let matches = mentions.matches(prompt: chat.prompt)
            if !matches.isEmpty {
                let selected = min(mentions.selection, matches.count - 1)
                switch event.keyCode {
                case 125:
                    mentions.selection = min(selected + 1, matches.count - 1)
                    return nil
                case 126:
                    mentions.selection = max(selected - 1, 0)
                    return nil
                case 36:
                    mentions.accept(matches[selected], in: chat)
                    return nil
                case 48 where !event.modifierFlags.contains(.shift):
                    mentions.accept(matches[selected], in: chat)
                    return nil
                case 53:
                    mentions.dismissed = true
                    return nil
                default:
                    break
                }
            }
            if event.keyCode == 53, zoomed.wrappedValue != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    zoomed.wrappedValue = nil
                }
                return nil
            }
            if event.keyCode == 53, chat.isBusy {
                if escArmed {
                    escDisarm?.cancel()
                    escArmed = false
                    Task { await chat.stop() }
                } else {
                    armEscInterrupt()
                }
                return nil
            }
            if event.keyCode == 48, event.modifierFlags.contains(.shift) {
                if let mode = chat.knobs.first(where: { $0.category == .mode }),
                   !mode.options.isEmpty {
                    let values = mode.options.map(\.value)
                    let at = values.firstIndex(of: mode.currentValue ?? "") ?? -1
                    let next = values[(at + 1) % values.count]
                    Task { await chat.choose(knob: mode.id, value: next) }
                }
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                let images = Self.pasteboardImages()
                if !images.isEmpty {
                    for data in images { chat.attach(imageData: data) }
                    return nil
                }
                if composerFocused,
                   let text = NSPasteboard.general.string(forType: .string),
                   chat.capturePaste(text) {
                    return nil
                }
            }
            return event
        }
    }

    static func pasteboardImages() -> [Data] {
        let board = NSPasteboard.general
        let types = board.types ?? []
        guard types.contains(.png) || types.contains(.tiff) else { return [] }
        return (board.readObjects(forClasses: [NSImage.self]) ?? [])
            .compactMap { object in
                guard let image = object as? NSImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff)
                else { return nil }
                return bitmap.representation(using: .png, properties: [:])
            }
    }

    func disarmEsc() {
        escDisarm?.cancel()
        escArmed = false
    }

    private func armEscInterrupt() {
        withAnimation(.easeOut(duration: 0.15)) { escArmed = true }
        escDisarm?.cancel()
        escDisarm = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { escArmed = false }
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
