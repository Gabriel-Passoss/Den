public enum PermissionMode: String, Equatable, Sendable, CaseIterable {
    case acceptEdits
    case auto
    case bypassPermissions
    case manual
    case dontAsk
    case plan
}
