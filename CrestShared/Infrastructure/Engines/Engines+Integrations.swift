import Foundation

extension Engines {
    /// Use the core's navigation engine choice, including site-specific rules.
    /// Unsupported engines never borrow another engine's signed-in session.
    func makeIntegrationSession(
        workspaceID: UUID, assignment: BrowserSpaceRuntimeAssignment, origin: URL,
        isAuthorized: @escaping @MainActor () -> Bool
    ) -> (any BrowserIntegrationSession)? {
        guard let site = SiteOrigin(url: origin) else { return nil }
        let query = IntegrationEngine(
            workspaceID: workspaceID, spaceID: assignment.spaceID,
            profileID: assignment.profileID, origin: site)
        guard let kind = (try? core.query(query))?.kind, let binding = bindings[kind] else { return nil }
        return binding.makeIntegrationSession(
            profileID: assignment.profileID, origin: origin,
            isAuthorized: { [weak self] in
                guard let self, isAuthorized() else { return false }
                return (try? self.core.query(query))?.kind == kind
            })
    }
}
