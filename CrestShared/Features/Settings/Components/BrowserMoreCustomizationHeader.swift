import SwiftUI

/// The row that opens and closes a page's More Customization: the settings
/// most people leave as they are, which follow it as their own groups.
struct BrowserMoreCustomizationHeader: View {
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            Button {
                withAnimation(CrestMotion.surface.unlessReducingMotion(reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: CrestSpacing.small) {
                    Text("More Customization")
                    Spacer(minLength: CrestSpacing.small)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityIdentifier("more-customization")
        }
    }
}
