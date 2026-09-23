import Foundation
import HarnessCore
@testable import DevSpace

func inertChat() -> ChatModel {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    return ChatModel(store: FileTranscriptStore(root: root),
                     workingDirectory: root,
                     harness: HarnessID(rawValue: "test-" + UUID().uuidString),
                     cache: scratchCache)
}
