import SwiftUI

/// One decision at a time, with the same live bindings in setup and Settings.
struct BrowserSpaceBrandingEditor: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    var previewName = ""
    var compact = false
    var showsPreview = true
    var dense = false
    var controlsBackground = BrowserOnboardingPalette.parchment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: BrowserSpaceAppearancePage?
    @State private var selectedDetail: BrowserSpaceAppearancePage?

    private var page: BrowserSpaceAppearancePage {
        destination ?? BrowserSpaceAppearanceLanding.page(for: branding)
    }

    private var editedBranding: Binding<BrowserSpaceBranding> {
        Binding(
            get: { branding },
            set: { value in
                var updated = value
                if page != .presets { updated.hasCustomAppearance = true }
                branding = updated
            })
    }

    private var detailPages: [BrowserSpaceAppearancePage] {
        switch page {
        case .crest: [.shape, .emblem, .border]
        case .pattern: [.layout, .division, .band]
        default: []
        }
    }

    private var contentPage: BrowserSpaceAppearancePage {
        if let selectedDetail, detailPages.contains(selectedDetail) { return selectedDetail }
        return detailPages.first ?? page
    }

    private var pinnedControls: PinnedScrollableViews {
        #if os(macOS)
            detailPages.isEmpty ? [] : [.sectionHeaders]
        #else
            []
        #endif
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: dense ? 12 : 18, pinnedViews: pinnedControls) {
            if showsPreview {
                BrowserSpaceAppearanceHero(branding: branding, symbol: symbol, name: previewName, compact: true)
                    .frame(height: 112)
            }
            Section {
                BrowserSpaceAppearanceChoices(
                    branding: editedBranding, symbol: $symbol, page: contentPage,
                    compact: compact, dense: dense, navigate: move
                )
                .id(contentPage)
                .transition(.opacity)
            } header: {
                controls
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(controlsBackground)
            }
        }
        .id("crest-space-appearance-top")
        .preference(key: BrowserSpaceAppearanceNavigationPreference.self, value: page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: branding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space appearance")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: dense ? 12 : 18) {
            VStack(alignment: .leading, spacing: 10) {
                if page != .presets {
                    Button {
                        move(to: page == .customize || page == .icon ? .presets : .customize)
                    } label: {
                        Label(
                            page == .customize || page == .icon ? "Select Template" : "All details",
                            systemImage: "chevron.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                }
                Text(page.title).font(CrestTypography.display(compact || dense ? 26 : 30))
                if page != .presets {
                    Text(page.detail)
                        .font(CrestTypography.sans(dense ? 12 : 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !detailPages.isEmpty {
                BrowserSpaceAppearanceLayerColors(branding: editedBranding, page: contentPage)
                    .frame(minHeight: page == .pattern ? 88 : 44, alignment: .top)
                BrowserSpaceAppearancePicker(
                    pages: detailPages, selection: contentPage, select: { selectedDetail = $0 })
                Text(contentPage.detail)
                    .font(CrestTypography.sans(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func move(to page: BrowserSpaceAppearancePage) {
        selectedDetail = nil
        destination = page
    }
}

#Preview("Visual Space Editor") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
    @Previewable @State var symbol = BrowserSpaceSimpleSymbol.work.rawValue
    ScrollView {
        BrowserSpaceBrandingEditor(branding: $branding, symbol: $symbol).padding(28)
    }
    .frame(width: 560, height: 720)
}

/// Hosts place this around their existing scroll container, keeping one scroll owner.
private struct BrowserSpaceAppearanceNavigationPreference: PreferenceKey {
    static let defaultValue = BrowserSpaceAppearancePage.presets
    static func reduce(value: inout BrowserSpaceAppearancePage, nextValue: () -> BrowserSpaceAppearancePage) {
        value = nextValue()
    }
}

extension View {
    func scrollsSpaceAppearancePages(anchorID: String = "crest-space-appearance-top") -> some View {
        ScrollViewReader { proxy in
            self.onPreferenceChange(BrowserSpaceAppearanceNavigationPreference.self) { _ in
                proxy.scrollTo(anchorID, anchor: .top)
            }
        }
    }
}
