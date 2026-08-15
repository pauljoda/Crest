import SwiftUI

struct BrowserSoftwareUpdateProgress: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Software update progress")
    }
}

#Preview {
    BrowserSoftwareUpdateProgress(progress: 0.42)
        .frame(width: 420)
        .padding()
}
