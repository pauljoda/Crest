import SwiftUI

/// Which way a Space's gradient runs down its sidebar, set on a dial, with
/// the angle beside it.
struct BrowserSpaceGradientAngleRow: View {
    // MARK: - Static Variables

    private static var dialSize: CGFloat { 44 }

    // MARK: - Variables

    let angle: CrestSettingValue<Double>
    /// The color the dial points in.
    let color: Color

    // MARK: - Actions - Drawing

    var body: some View {
        CrestSettingRow("Gradient angle", setting: angle.resettable("Gradient angle")) {
            HStack(spacing: CrestSpacing.medium) {
                Text("\(Int(angle.wrappedValue.rounded()))°").monospacedDigit().foregroundStyle(.secondary)
                BrowserSpaceGradientAngleDial(angle: angle.binding, color: color)
                    .frame(width: Self.dialSize, height: Self.dialSize)
            }
        }
    }
}

#if DEBUG
    #Preview("Gradient angle") {
        @Previewable @State var angle = 90.0
        Form {
            BrowserSpaceGradientAngleRow(
                angle: CrestSettingValue($angle, default: 90), color: SpaceHouse.winter.look.secondaryColor.color)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 120)
    }
#endif
