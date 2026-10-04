import Foundation
import HarnessCore

extension ChatModel {
    func captureMemory(atLeast threshold: Int) {
        guard let memory else { return }
        let session = sessionID
        let spoken = entries
        let directory = workingDirectory
        let harness = harness
        Task {
            await memory.capture(session: session, entries: spoken, directory: directory,
                                 harness: harness, atLeast: threshold)
        }
    }
}
