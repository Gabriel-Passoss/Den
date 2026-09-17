/// O que um harness sabe fazer.
///
/// Existe para impedir que a abstração vire ficção (spec §10): a UI lê estas
/// bandeiras e esconde o que o harness atual não suporta, em vez de oferecer
/// ações que falham. Todo default é `false` — um harness só ganha um botão
/// depois de declarar que o sustenta.
public struct HarnessCapabilities: Equatable, Sendable {
    /// Encaminha pedidos de permissão ao cliente em vez de decidir sozinho.
    /// Sem isto, não existe diálogo de aprovação: o harness já decidiu.
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
