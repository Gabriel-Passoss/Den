import SwiftUI

struct WorktreeNote {
    let text: String
    let isProgress: Bool
    let tint: Color
}

extension WorktreeModel {
    func note(for chat: ChatModel) -> WorktreeNote? {
        switch phase(for: chat.sessionID) {
        case .creating(let step): return WorktreeNote(text: step, isProgress: true, tint: Theme.accentSoft)
        case .failed(let message): return WorktreeNote(text: message, isProgress: false, tint: Theme.modified)
        case nil: break
        }
        if let blocker = blocker(for: chat) {
            return WorktreeNote(text: blocker, isProgress: false, tint: Theme.removed)
        }
        if let warning = warnings[chat.sessionID] {
            return WorktreeNote(text: warning, isProgress: false, tint: Theme.modified)
        }
        return nil
    }
}

struct WorktreeNoteLabel: View {
    let note: WorktreeNote

    var body: some View {
        if note.isProgress {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(note.tint)
        }
        Text(note.text)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 520)
    }
}
