import Foundation

/// What a window's page runtime follows in its workspace: tab icons, content
/// blocking and credential access, compared between changes so each is
/// reconciled only when it moved.
struct BrowserRuntimeSessionProjection: Equatable, Sendable {
    // MARK: - Variables

    let tabIconState: BrowserTabIconSessionState
    let contentBlockingState: BrowserContentBlockingSessionState
    let credentialAccessState: [UUID: Bool]

    // MARK: - Initializers

    /// What `workspace` in the read model holds now, its tabs wearing the
    /// icons `images` keeps, and its pages blocking as `contentBlocking` says.
    @MainActor
    init(workspace: WorkspaceModel?, images: FaviconAssets, contentBlocking: ContentBlockingPolicy) {
        tabIconState = BrowserTabIconSessionState(workspace: workspace, images: images)
        contentBlockingState = BrowserContentBlockingSessionState(workspace: workspace, policy: contentBlocking)
        credentialAccessState = Dictionary(
            uniqueKeysWithValues: (workspace?.spaces.models ?? []).map {
                ($0.id, $0.settings.credentialPreferences.isEnabled)
            })
    }
}
