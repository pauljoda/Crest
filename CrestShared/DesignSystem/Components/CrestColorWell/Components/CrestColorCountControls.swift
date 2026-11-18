import SwiftUI

/// Minus and plus centered just below the color wheel: minus takes the
/// chosen color out, which pops away while the rest stay, and plus adds one
/// where color theory puts it, which pops in and becomes the chosen one.
struct CrestColorCountControls: View {
    // MARK: - Variables

    @Binding var fill: CrestColorFill
    @Binding var selection: Int
    @Binding var stops: CrestColorStops

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        HStack(spacing: CrestColorCountControlsMetrics.spacing) {
            Button("Remove Color", systemImage: "minus", action: remove)
                .disabled(!fill.canRemoveColor)
                .help(Text("Remove Color"))
            Button("Add Color", systemImage: "plus", action: add)
                .disabled(!fill.canAddColor)
                .help(Text("Add Color"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle(controlSize: CrestColorPopoverMetrics.control, showsRestingFill: true))
    }

    // MARK: - Mutators

    private func add() {
        withAnimation(CrestMotion.colorPop.unlessReducingMotion(reduceMotion)) {
            stops.add(to: &fill)
            selection = fill.colors.count - 1
        }
    }

    private func remove() {
        let index = selection
        withAnimation(CrestMotion.colorPop.unlessReducingMotion(reduceMotion)) {
            stops.remove(at: index, from: &fill)
            selection = min(index, fill.colors.count - 1)
        }
    }
}

enum CrestColorCountControlsMetrics {
    static let spacing: CGFloat = 12
}
