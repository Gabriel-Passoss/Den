enum ContextLevel: Equatable {
    case calm
    case warning

    case critical

    init(fraction: Double) {
        switch fraction {
        case ..<0.5: self = .calm
        case ..<0.8: self = .warning
        default: self = .critical
        }
    }
}
