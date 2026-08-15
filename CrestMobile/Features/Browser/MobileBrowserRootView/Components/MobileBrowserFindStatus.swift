import SwiftUI

struct MobileBrowserFindStatus: View {
    let state: BrowserFindMatchState

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView()
                .controlSize(.small)
                .frame(
                    width: MobileBrowserChromeLayout.findStatusWidth,
                    height: CrestLayout.minimumHitTarget
                )
                .accessibilityLabel("Searching")
                .accessibilityIdentifier("find-result")
        case .found:
            resultImage(
                systemName: "checkmark.circle.fill",
                color: .green,
                label: "Match found"
            )
        case .notFound:
            resultImage(
                systemName: "exclamationmark.circle.fill",
                color: .red,
                label: "No match"
            )
        }
    }

    private func resultImage(
        systemName: String,
        color: Color,
        label: String
    ) -> some View {
        Image(systemName: systemName)
            .foregroundStyle(color)
            .frame(
                width: MobileBrowserChromeLayout.findStatusWidth,
                height: CrestLayout.minimumHitTarget
            )
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier("find-result")
    }
}

#Preview("Mobile Browser Find Status", traits: .sizeThatFitsLayout) {
    MobileBrowserFindStatus(state: .found)
}
