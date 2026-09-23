import Foundation
import HarnessCore

public extension ClaudeEventMapper {

    func entry(for request: PermissionRequest, raw: JSONValue) -> TranscriptEntry {
        TranscriptEntry(timestamp: now(), kind: .permissionRequest(request), raw: raw)
    }

    func entry(for decision: PermissionDecision, requestID: String,
               raw: JSONValue) -> TranscriptEntry {
        TranscriptEntry(
            timestamp: now(),
            kind: .permissionDecision(requestID: requestID, decision),
            raw: raw
        )
    }
}
