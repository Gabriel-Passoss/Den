import Testing
import Foundation
import AppKit
@testable import DevSpace

private func pngData(width: Int, height: Int) throws -> Data {
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    rep.size = CGSize(width: width, height: height)
    return try #require(rep.representation(using: .png, properties: [:]))
}

@Test func displaySizeShrinksLargeImagesIntoTheBox() throws {
    let size = ImageCache.displaySize(for: try pngData(width: 560, height: 440))
    #expect(size == CGSize(width: 280, height: 220))
}

@Test func displaySizeNeverEnlargesSmallImages() throws {
    let size = ImageCache.displaySize(for: try pngData(width: 100, height: 50))
    #expect(size == CGSize(width: 100, height: 50))
}

@Test func displaySizeHonoursTheTighterDimension() throws {
    let size = ImageCache.displaySize(for: try pngData(width: 280, height: 880))
    #expect(size == CGSize(width: 70, height: 220))
}

@Test func displaySizeOfGarbageIsZero() {
    #expect(ImageCache.displaySize(for: Data([0x00, 0x01])) == .zero)
    #expect(ImageCache.decodedImage(Data([0x00, 0x01])) == nil)
}
