import Foundation
import DenStore

nonisolated struct MemoryCaptureMark: Codable, Equatable, Sendable {
    static let documentKind = "memory-capture"

    var lastEntry: UUID
    var capturedAt: Date
}

extension Repositories {
    nonisolated var memoryMarks: any SessionDocumentRepository<MemoryCaptureMark> {
        documents(kind: MemoryCaptureMark.documentKind, as: MemoryCaptureMark.self)
    }
}
