import SwiftUI
import AppKit

enum ImageCache {
    private static let decodedImages = NSCache<NSData, NSImage>()

    static func decodedImage(_ data: Data) -> NSImage? {
        let key = data as NSData
        if let cached = decodedImages.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        decodedImages.setObject(image, forKey: key)
        return image
    }

    static func displaySize(for data: Data) -> CGSize {
        guard let image = decodedImage(data),
              image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(1, min(280 / image.size.width, 220 / image.size.height))
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}
