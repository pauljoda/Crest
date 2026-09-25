#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: a section's header. It
    /// reads nothing observed; it redraws only for new inputs.
    struct ReadModelSpikeSectionHeader: View {
        let placement: TabPlacement
        let isExpanded: Bool

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.sectionHeader)
            #endif
            HStack {
                Text(placement.title).font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption2)
            }
            .padding(.top, 8)
        }
    }
#endif
