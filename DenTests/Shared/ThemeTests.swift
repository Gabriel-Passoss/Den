import SwiftUI
import Testing
@testable import Den

@Test func thePetColorsMatchTheDesign() {
    #expect(Theme.petSpec == Color(hex: 0x5AA9F2))
    #expect(Theme.petImpl == Color(hex: 0xC98A5A))
    #expect(Theme.petTest == Color(hex: 0x2FBFA8))
    #expect(Theme.petStd == Color(hex: 0x9B7BEA))
    #expect(Theme.petPr == Color(hex: 0xE57FB0))
}

@Test func theFaintTextIsReadableOnTheCanvas() {
    #expect(Theme.textFaint == Color(hex: 0x767D90))
    #expect(contrast(0x767D90, 0x0F1115) >= 4.5)
}

@Test func theTypeScaleKeepsItsSteps() {
    let scale = [Theme.font10, Theme.font11, Theme.font12, Theme.font13,
                 Theme.font14, Theme.font17, Theme.font24]
    #expect(scale == [10, 11, 12, 13, 14, 17, 24])
}

@Test func theSpacingScaleKeepsItsSteps() {
    let scale = [Theme.space2, Theme.space4, Theme.space6, Theme.space8, Theme.space10,
                 Theme.space12, Theme.space16, Theme.space20, Theme.space24]
    #expect(scale == [2, 4, 6, 8, 10, 12, 16, 20, 24])
}

@Test func theRadiusScaleKeepsItsSteps() {
    let scale = [Theme.radius4, Theme.radius6, Theme.radius8,
                 Theme.radius10, Theme.radius12, Theme.radius16]
    #expect(scale == [4, 6, 8, 10, 12, 16])
}

private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
    let luminances = [luminance(first), luminance(second)].sorted(by: >)
    return (luminances[0] + 0.05) / (luminances[1] + 0.05)
}

private func luminance(_ hex: UInt32) -> Double {
    let channels = [hex >> 16, hex >> 8, hex].map { channel -> Double in
        let value = Double(channel & 0xFF) / 255
        return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}
