#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: a sidebar over one Space
    /// of the read model, to measure how many bodies each kind of change
    /// redraws before the real sidebar moves off the session copy. Nothing
    /// ships it; `CoreReadModelTests` mirrors each view's reads.
    struct ReadModelSpikeSidebar: View {
        let workspace: WorkspaceModel
        let space: SpaceModel
        let window: WindowStateModel
        let outline: ReadModelSpikeOutline
        let state: CoreState
        var isLazy = true

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ReadModelSpikeSwitcher(workspace: workspace, shownSpaceID: space.id)
                ReadModelSpikeHeader(settings: space.settings)
                ReadModelSpikeList(space: space, window: window, outline: outline, state: state, isLazy: isLazy)
            }
            .padding(10)
            .frame(width: 280)
        }
    }
#endif
