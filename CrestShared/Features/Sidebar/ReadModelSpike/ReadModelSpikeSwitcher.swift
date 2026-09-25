#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: the Space switcher. It
    /// reads the workspace's Spaces in order and hands each segment its
    /// settings, so a renamed Space redraws only its own segment.
    struct ReadModelSpikeSwitcher: View {
        // MARK: - Types

        /// One segment and the inputs the switcher hands it.
        struct Segment: Equatable, Identifiable {
            let id: UUID
            let settings: SpaceSettingsModel
            let isShown: Bool

            static func == (lhs: Segment, rhs: Segment) -> Bool {
                lhs.id == rhs.id && lhs.settings === rhs.settings && lhs.isShown == rhs.isShown
            }
        }

        // MARK: - Variables

        let workspace: WorkspaceModel
        let shownSpaceID: UUID

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.switcher)
            #endif
            HStack(spacing: 4) {
                ForEach(Self.segments(workspace: workspace, shownSpaceID: shownSpaceID)) { segment in
                    ReadModelSpikeSwitcherSegment(settings: segment.settings, isShown: segment.isShown)
                }
            }
        }

        // MARK: - Actions - Reading

        /// Everything the switcher's body reads, as the segments it shows.
        @MainActor
        static func segments(workspace: WorkspaceModel, shownSpaceID: UUID) -> [Segment] {
            workspace.spaces.models.map { Segment(id: $0.id, settings: $0.settings, isShown: $0.id == shownSpaceID) }
        }
    }
#endif
