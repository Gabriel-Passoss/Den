import Foundation

public struct MediaAttachment: Sendable, Equatable {
    public let mediaType: String
    public let data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }

    public var isImage: Bool { mediaType.hasPrefix("image/") }
}

public struct UserTurn: Sendable, Equatable {
    public var text: String
    public var attachments: [MediaAttachment]

    public init(text: String, attachments: [MediaAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }
}
