import SwiftUI

/// The same sidebar preview used by import and setup, dressed in the live draft.
struct BrowserSpaceAppearanceHero: View {
    let branding: BrowserSpaceBranding
    let symbol: String
    var name = ""
    var compact = false
    var space: BrowserSpace? = nil
    var editableName: Binding<String>? = nil
    var showsNameHint = false
    var spacePicker: BrowserSpaceCustomizationPicker? = nil
    @State private var exampleTab = BrowserTab(title: String(localized: "Start Page"), url: nil, placement: .current)

    private var preview: BrowserSpace {
        var value = space ?? BrowserSession.showcase.spaces[0]
        value.branding = branding
        value.symbol = symbol
        value.name = name.isEmpty ? String(localized: "Your Space") : name
        return value
    }

    private var nameHint: LocalizedStringKey {
        #if os(iOS)
            "Tap the name to rename"
        #else
            "Click the name to rename"
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrowserSpaceIdentityIcon(space: preview, size: 34)
                    .frame(width: 34, height: 34)
                if let editableName {
                    BrowserInlineSpaceName(
                        name: editableName, size: 16,
                        titleFont: CrestTypography.sans(16, weight: .semibold))
                } else {
                    Text(preview.name).font(CrestTypography.sans(16, weight: .semibold)).lineLimit(1)
                    Spacer()
                }
            }
            .padding(18)
            if showsNameHint {
                Text(nameHint)
                    .font(CrestTypography.sans(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
            if !compact {
                BrowserSpaceSidebarPreview(space: preview)
            } else {
                #if os(iOS)
                    BrowserSpaceSidebarTabRow(tab: exampleTab, profileID: preview.profile.id, isSelected: true)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                #else
                    PinnedTabGrid(
                        tabs: preview.pinnedTabs, assignment: BrowserSpaceRuntimeAssignment(space: preview),
                        selectedTabID: nil, select: { _ in }
                    )
                    .padding(.horizontal, 14).padding(.bottom, 12)
                    .allowsHitTesting(false)
                #endif
            }
            if let spacePicker {
                spacePicker
            }
        }
        .background { BrowserSpaceBannerBackground(branding: branding) }
        .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: branding))
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: editableName == nil && spacePicker == nil ? .ignore : .contain)
        .accessibilityLabel("Live sidebar preview for \(preview.name)")
    }
}
