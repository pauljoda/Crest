import SwiftUI

/// Picks one Space out of many in a form context.
///
/// A native `Picker` retains the platform menu, keyboard behavior, accessibility
/// role, and selected-value announcement. Crest standardizes the identity row.
struct CrestSpaceMenuPicker<Tag: Hashable>: View {
    let label: LocalizedStringKey
    let spaces: [CrestSpaceIdentity]
    @Binding var selection: Tag
    let tag: (CrestSpaceIdentity) -> Tag
    var labelsHidden = false
    var iconSize: CGFloat = CrestSpaceChipMetrics.menuIconSize
    var accessibilityIdentifier: String?

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(spaces) { identity in
                BrowserSpaceIdentityLabel(
                    space: identity.space,
                    title: identity.name,
                    iconSize: iconSize
                )
                .tag(tag(identity))
            }
        }
        .modifier(CrestSpaceMenuLabelVisibility(labelsHidden: labelsHidden))
        .accessibilityLabel(Text(label))
        .crestAccessibilityIdentifier(accessibilityIdentifier)
    }
}
