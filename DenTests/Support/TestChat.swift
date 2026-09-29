import Foundation
import HarnessCore
@testable import Den

func inertChat() -> ChatModel {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    return ChatModel(store: FileTranscriptStore(root: root),
                     workingDirectory: root,
                     harness: HarnessID(rawValue: "test-" + UUID().uuidString),
                     cache: scratchCache)
}
