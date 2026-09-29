public struct HarnessCapabilities: Equatable, Sendable {

    public var routesPermissionRequests: Bool
    public var canInterrupt: Bool
    public var canSetPermissionMode: Bool
    public var canSetModelInSession: Bool
    public var canSetEffortInSession: Bool
    public var canResumeSession: Bool
    public var canForkSession: Bool

    public init(
        routesPermissionRequests: Bool = false,
        canInterrupt: Bool = false,
        canSetPermissionMode: Bool = false,
        canSetModelInSession: Bool = false,
        canSetEffortInSession: Bool = false,
        canResumeSession: Bool = false,
        canForkSession: Bool = false
    ) {
        self.routesPermissionRequests = routesPermissionRequests
        self.canInterrupt = canInterrupt
        self.canSetPermissionMode = canSetPermissionMode
        self.canSetModelInSession = canSetModelInSession
        self.canSetEffortInSession = canSetEffortInSession
        self.canResumeSession = canResumeSession
        self.canForkSession = canForkSession
    }

    /// Whether a knob of this category reaches the running CLI without a
    /// relaunch.
    public func canChangeInSession(_ category: HarnessKnob.Category) -> Bool {
        switch category {
        case .model: canSetModelInSession
        case .effort: canSetEffortInSession
        case .mode: canSetPermissionMode
        }
    }
}
