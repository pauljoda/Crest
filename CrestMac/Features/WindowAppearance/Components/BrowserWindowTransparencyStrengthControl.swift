import SwiftUI

struct BrowserWindowTransparencyStrengthControl: View {
    @Binding var strength: Double
    let isEnabled: Bool

    var body: some View {
        LabeledContent("Transparency") {
            HStack(spacing: CrestSpacing.small) {
                Slider(
                    value: $strength,
                    in: BrowserWindowTransparencyPolicy.strengthRange
                )
                .frame(minWidth: 180)

                Text(strength, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .disabled(!isEnabled)
    }
}

#Preview("Transparency strength") {
    @Previewable @State var strength = 0.18
    Form {
        BrowserWindowTransparencyStrengthControl(
            strength: $strength,
            isEnabled: true
        )
    }
    .frame(width: 480)
}
