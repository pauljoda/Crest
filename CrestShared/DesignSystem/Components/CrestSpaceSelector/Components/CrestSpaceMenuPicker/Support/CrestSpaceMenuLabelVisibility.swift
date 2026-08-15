import SwiftUI

struct CrestSpaceMenuLabelVisibility: ViewModifier {
    let labelsHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if labelsHidden {
            content.labelsHidden()
        } else {
            content
        }
    }
}

#Preview("Space Menu Label Visibility", traits: .sizeThatFitsLayout) {
    @Previewable @State var selection =
        CrestSpaceSelectorPreviewFixture.selectedSpaceID(for: .menu)

    Form {
        Picker("Labeled Space", selection: $selection) {
            ForEach(CrestSpaceSelectorPreviewFixture.identities) { identity in
                Text(verbatim: identity.name)
                    .tag(Optional(identity.id))
            }
        }
        .modifier(CrestSpaceMenuLabelVisibility(labelsHidden: false))

        Picker("Hidden Space Label", selection: $selection) {
            ForEach(CrestSpaceSelectorPreviewFixture.identities) { identity in
                Text(verbatim: identity.name)
                    .tag(Optional(identity.id))
            }
        }
        .modifier(CrestSpaceMenuLabelVisibility(labelsHidden: true))
        .accessibilityLabel("Hidden Space Label")
    }
    .formStyle(.grouped)
    .frame(width: 360)
    .environment(\.displayScale, 2)
    .preferredColorScheme(.light)
}
