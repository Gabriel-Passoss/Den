public enum SessionStart: Sendable, Equatable {

    case fresh

    case resume(harnessSessionID: String)

    case fork(from: String)
}
