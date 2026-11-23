import SwiftUI

/// The houses as templates, simple then heraldic, each a full set shown as
/// it comes: its crest standing on a short sidebar in its own colors.
/// Choosing one gives the Space the crest and the colors together. Where
/// that replaces colors the person made, the window offers to undo it.
/// Setup's Space page and a Space's appearance in Settings show it first,
/// before the colors and the icon that refine it.
struct BrowserSpaceTemplatePicker: View {
    // MARK: - Variables

    @Binding var branding: SpaceBranding
    /// Whether applying a template over the person's own colors offers to
    /// undo it in the window's notice, for a page in the browser window.
    var offersUndo = false

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserSpaceIconPickerMetrics.styleSpacing) {
            ForEach(SpaceHouseStyle.all, id: \.self) { style in
                VStack(alignment: .leading, spacing: CrestSpacing.small) {
                    Text(style.title)
                        .crestCapsLabel()
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 80), spacing: CrestSpacing.small)],
                        spacing: CrestSpacing.small
                    ) {
                        ForEach(SpaceHouse.all.filter { $0.style == style }, id: \.self) { house in
                            template(house)
                        }
                    }
                }
            }
        }
        .padding(.vertical, CrestSpacing.extraSmall)
        .accessibilityIdentifier("space-templates")
    }

    /// One template, drawn in its own colors and nothing of the Space's, so
    /// editing the Space never redraws it.
    private func template(_ house: SpaceHouse) -> some View {
        BrowserCrestStudioChoice(title: house.title, selected: house.isWorn(by: branding)) {
            apply(house)
        } artwork: {
            BrowserSpaceTemplateArtwork(house: house)
                .equatable()
        }
        .accessibilityIdentifier("space-template-\(house.name)")
    }

    // MARK: - Mutators

    /// Gives the Space `house`'s crest and colors, offering to put back the
    /// colors it replaces when the person made them.
    private func apply(_ house: SpaceHouse) {
        let previous = branding
        let applied = house.applying(to: previous)
        guard applied != previous else { return }
        branding = applied
        guard offersUndo, previous.colors != applied.colors || previous.colorGradients != applied.colorGradients,
            !SpaceHouse.all.contains(where: { $0.isWorn(by: previous) })
        else { return }
        let restore = $branding
        BrowserNoticeCenter.shared.post(
            BrowserNotice(
                message: String(localized: "Applied \(String(localized: house.title))"),
                systemImage: "paintpalette",
                action: BrowserNoticeAction(title: String(localized: "Undo")) {
                    restore.wrappedValue = previous
                }))
    }
}

/// A template as it comes: the house's crest standing on a short sidebar in
/// the house's own Background and texture.
private struct BrowserSpaceTemplateArtwork: View, Equatable {
    let house: SpaceHouse

    var body: some View {
        ZStack {
            BrowserSpaceBannerBackground(branding: house.look)
                .clipShape(.rect(cornerRadius: CrestRadius.compact, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
                        .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
                }
            BrowserSpaceCrestIcon(
                branding: house.look, size: BrowserSpaceTemplatePickerMetrics.crestSize, rasterizesLayers: false
            )
            .equatable()
        }
    }
}

enum BrowserSpaceTemplatePickerMetrics {
    /// The crest on a template's sidebar, small enough to leave the sidebar's
    /// colors showing round it.
    static let crestSize: CGFloat = 40
}

#if DEBUG
    #Preview("Space templates") {
        @Previewable @State var branding = SpaceHouse.winter.look
        Form {
            Section {
                BrowserSpaceTemplatePicker(branding: $branding)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }
#endif
