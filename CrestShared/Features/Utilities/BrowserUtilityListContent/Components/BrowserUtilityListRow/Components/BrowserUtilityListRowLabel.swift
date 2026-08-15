import SwiftUI

struct BrowserUtilityListRowLabel<Icon: View, Trailing: View>: View {
    let title: String
    let subtitle: Text
    let subtitleIsFailure: Bool
    let icon: Icon
    let trailing: Trailing

    init(
        title: String,
        subtitle: Text,
        subtitleIsFailure: Bool = false,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleIsFailure = subtitleIsFailure
        self.icon = icon()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                subtitle
                    .font(.caption)
                    .foregroundStyle(
                        subtitleIsFailure
                            ? AnyShapeStyle(.red)
                            : AnyShapeStyle(.secondary)
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
    }
}

#Preview("Utility List Row Label", traits: .fixedLayout(width: 360, height: 72)) {
    BrowserUtilityListRowLabel(
        title: BrowserUtilityListPreviewFixture.historyEntry.title,
        subtitle: Text("Visited 3 times")
    ) {
        Image(systemName: "globe")
    } trailing: {
        Image(systemName: "arrow.up.forward")
            .foregroundStyle(.tertiary)
    }
    .padding()
}
