public struct HarnessCapabilities: Equatable, Sendable {

    public var routesPermissionRequests: Bool
    public var canInterrupt: Bool
    public var canSetPermissionMode: Bool
    public var canSetModelInSession: Bool
    public var canResumeSession: Bool
    public var canForkSession: Bool

    public init(
        routesPermissionRequests: Bool = false,
        canInterrupt: Bool = false,
        canSetPermissionMode: Bool = false,
        canSetModelInSession: Bool = false,
        canResumeSession: Bool = false,
        canForkSession: Bool = false
    ) {
        self.routesPermissionRequests = routesPermissionRequests
        self.canInterrupt = canInterrupt
        self.canSetPermissionMode = canSetPermissionMode
        self.canSetModelInSession = canSetModelInSession
        self.canResumeSession = canResumeSession
        self.canForkSession = canForkSession
    }
}
