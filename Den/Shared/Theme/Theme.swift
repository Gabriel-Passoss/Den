import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let canvas = Color(hex: 0x0F1115)
    static let sidebar = Color(hex: 0x14171D)
    static let panel = Color(hex: 0x121419)
    static let raised = Color(hex: 0x1A1E26)
    static let field = Color(hex: 0x1D212A)
    static let card = Color(hex: 0x161920)
    static let bubble = Color(hex: 0x232836)
    static let hover = Color(hex: 0x222631)
    static let hoverRaised = Color(hex: 0x282D39)
    static let selected = Color(hex: 0x2F3442)
    static let terminal = Color(hex: 0x0A0C0F)
    static let terminalBar = Color(hex: 0x1B1F27)

    static let border = Color(hex: 0x242833)
    static let borderCard = Color(hex: 0x272C38)
    static let borderStrong = Color(hex: 0x2F3542)
    static let borderControl = Color(hex: 0x363C4B)

    static let text = Color(hex: 0xE6E9F0)
    static let textSecondary = Color(hex: 0xB8BFCE)
    static let textMuted = Color(hex: 0x9AA2B4)
    static let textTertiary = Color(hex: 0x7F879A)
    static let textFaint = Color(hex: 0x555C6C)

    static let accent = Color(hex: 0x8B93FF)
    static let accentSoft = Color(hex: 0xA8AEFF)
    static let accentFill = Color(hex: 0x1D2035)
    static let action = Color(hex: 0x6E78F7)
    static let onAction = Color(hex: 0xFFFFFF)

    static let added = Color(hex: 0x7FCB92)
    static let addedFill = Color(hex: 0x16291C)
    static let removed = Color(hex: 0xF08C7E)
    static let removedFill = Color(hex: 0x351C18)
    static let modified = Color(hex: 0xE0B45F)
    static let renamed = Color(hex: 0xC3AEF0)
    static let hunk = Color(hex: 0x93AEE8)
    static let hunkFill = Color(hex: 0x1B2233)
    static let waiting = Color(hex: 0xC3AEF0)
    static let success = Color(hex: 0x2F8A4A)

    static let alertFill = Color(hex: 0x1F1B12)
    static let alertBorder = Color(hex: 0x4D3F1F)
    static let alertText = Color(hex: 0xEBC46A)

    static let headerHeight: CGFloat = 52
    static let trafficLightsInset: CGFloat = 78
}

struct DenButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }

    var kind: Kind
    var radius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind, radius: radius)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        let radius: CGFloat

        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .foregroundStyle(foreground)
                .background(background, in: shape)
                .overlay {
                    if kind == .secondary {
                        shape.strokeBorder(Theme.borderControl, lineWidth: 1)
                    }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onAction
            case .secondary, .ghost: Theme.text
            }
        }

        private var background: Color {
            let active = isEnabled && (hovering || configuration.isPressed)
            switch kind {
            case .primary:
                return configuration.isPressed ? Theme.action.opacity(0.85)
                    : active ? Theme.accent : Theme.action
            case .secondary:
                return active ? Theme.hoverRaised : Theme.raised
            case .ghost:
                return configuration.isPressed ? Theme.hoverRaised
                    : active ? Theme.hover : .clear
            }
        }
    }
}

extension ButtonStyle where Self == DenButtonStyle {
    static var denPrimary: DenButtonStyle { DenButtonStyle(kind: .primary) }
    static var denSecondary: DenButtonStyle { DenButtonStyle(kind: .secondary) }
    static var denGhost: DenButtonStyle { DenButtonStyle(kind: .ghost) }
    static func denGhost(radius: CGFloat) -> DenButtonStyle {
        DenButtonStyle(kind: .ghost, radius: radius)
    }
}

struct PillLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 32)
    }
}

struct ChipLabel: ViewModifier {
    var horizontalPadding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12.5))
            .padding(.horizontal, horizontalPadding)
            .frame(height: 30)
            .contentShape(Rectangle())
    }
}

struct IconLabel: ViewModifier {
    var size: CGFloat = 30

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }
}

extension View {
    func pillLabel() -> some View { modifier(PillLabel()) }

    func iconLabel(size: CGFloat = 30) -> some View { modifier(IconLabel(size: size)) }

    func chipLabel(horizontalPadding: CGFloat = 10) -> some View {
        modifier(ChipLabel(horizontalPadding: horizontalPadding))
    }

    func onKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers,
                            perform action: @escaping () -> Void) -> some View {
        background {
            Button("", action: action)
                .keyboardShortcut(key, modifiers: modifiers)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    func hoverFill(_ hovering: Bool = false, selected: Bool = false, radius: CGFloat = 8) -> some View {
        background(selected ? Theme.hover : hovering ? Theme.hover.opacity(0.7) : .clear,
                   in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct ChipSurface: ViewModifier {
    var bordered = false
    var radius: CGFloat = 8
    var hovering = false
    var open = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let active = hovering || open
        return content
            .background(bordered ? (active ? Theme.hoverRaised : Theme.raised)
                                 : (active ? Theme.hover : .clear), in: shape)
            .overlay {
                if bordered { shape.strokeBorder(Theme.borderStrong, lineWidth: 1) }
            }
    }
}

extension View {
    func chipSurface(bordered: Bool = false, radius: CGFloat = 8,
                     hovering: Bool = false, open: Bool = false) -> some View {
        modifier(ChipSurface(bordered: bordered, radius: radius,
                             hovering: hovering, open: open))
    }
}

struct Chevron: View {
    var size: CGFloat = 9

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
    }
}
