import SwiftUI

/// The customization style a Space shows its own look in: the style every
/// Space follows, marked Default, or one of its own. Reset has it follow the
/// Appearance setting again. Choosing a style gives the Space its look in it.
struct BrowserSpaceStyleSection: View {
    // MARK: - Variables

    let spaceID: UUID
    @Binding var branding: SpaceBranding
    private let appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        let following = CrestResettableSetting(
            title: "Style", isDefault: !appearance.hasOwnCustomizationStyle(spaceID)
        ) {
            choose(nil)
        }
        CrestSettingsGroup("Style", settings: [following]) {
            BrowserCustomizationStyleChoices(
                selection: appearance.customizationStyle(for: spaceID), spaceIcons: appearance.chosenSpaceIcons
            ) { chosen in
                choose(chosen)
            } badge: { style in
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(style == appearance.customizationStyle ? 1 : 0)
                    .accessibilityHidden(style != appearance.customizationStyle)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("space-customization-style")
        }
    }

    // MARK: - Mutators

    /// Gives the Space `style` of its own, or has it follow the shared style
    /// when `style` is nil, in its look for the style it then shows.
    private func choose(_ style: BrowserCustomizationStyle?) {
        let previous = appearance.customizationStyle(for: spaceID)
        withAnimation(CrestMotion.styleChange.unlessReducingMotion(reduceMotion)) {
            appearance.setCustomizationStyle(style, for: spaceID)
            branding = appearance.look(
                of: spaceID, wearing: branding, movingFrom: previous, to: appearance.customizationStyle(for: spaceID))
        }
    }
}
