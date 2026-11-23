import SwiftUI

/// The row of actions over the editor's list, its slots numbered and the
/// chosen one outlined. An action dragged onto the row lands where it is let
/// go, and choosing a slot makes it the one the next chosen action goes in.
struct SiteControlsActionSlots: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SiteControlsActionRow(model: model, isEditing: true)
            hint
                .font(metrics.detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private var hint: Text {
        #if os(iOS)
            Text("Touch and hold an action to drag it in, out and along the row, or choose a slot and then an action.")
        #else
            Text("Drag actions in, out and along the row, or choose a slot and then an action.")
        #endif
    }
}
