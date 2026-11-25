public struct Stage: Sendable, Equatable, Identifiable {
    public let id: StageID
    public internal(set) var name: String
    public internal(set) var agent: AgentID?
    public internal(set) var isFinal: Bool

    public init(id: StageID = StageID(), name: String, agent: AgentID? = nil, isFinal: Bool = false) {
        self.id = id
        self.name = name
        self.agent = agent
        self.isFinal = isFinal
    }
}
