import Foundation

/// How much of Crest's customization a person sees. Heraldic shows every
/// control; Modern and Simple show fewer and simpler ones, and leave the rest
/// in Advanced at the end of each page. Each style is the setup look of the
/// same name, and is stored by that name.
///
/// The three instances below are the one table of what each style shows.
struct BrowserCustomizationStyle: Hashable, Sendable, Identifiable {
    // MARK: - Static Variables

    /// Today's customization: every control on every page.
    static let heraldic = BrowserCustomizationStyle(look: .heraldic, spaceIcons: .icons, settings: nil)

    /// The choices that change how Crest reads and behaves, without the fine
    /// tuning of fills, borders and highlights.
    static let modern = BrowserCustomizationStyle(
        look: .modern, spaceIcons: .icons,
        settings: [
            .sidebarOnRight, .appearanceMode, .followSpaceAccent, .spacePageMotion, .fullScreenSidebarReveal,
            .spaceShortcutSidebarReveal, .defaultPageZoom, .cornerRadius, .tabScale, .pinLayout, .websitePinColors,
            .dimUnloadedTabs, .tabStatus,
            .addressDisplay, .copyURLButton, .superCopy, .folderIconOnly, .folderTabCounts, .appIcon,
        ])

    /// The few choices most people make, with Space icons as dots.
    static let simple = BrowserCustomizationStyle(
        look: .simple, spaceIcons: .dots,
        settings: [.sidebarOnRight, .appearanceMode, .defaultPageZoom, .tabScale, .appIcon])

    static let all = [heraldic, modern, simple]
    static let standard = heraldic

    // MARK: - Variables

    /// The setup look of the same name, which Spaces made in this style wear.
    let look: SetupLook
    /// How the Space switcher shows Spaces in this style until the person
    /// chooses for themself.
    let spaceIcons: BrowserSpaceIconDisplay
    /// The Appearance settings this style keeps on the page, or nil for every
    /// one.
    private let settings: Set<BrowserAppearanceSetting>?

    /// The persisted spelling.
    var name: String { look.name }
    var title: LocalizedStringResource { look.title }
    var id: String { name }
    /// Whether this style leaves any Appearance setting for Advanced.
    var hidesSettings: Bool { settings != nil }

    // MARK: - Initializers

    private init(look: SetupLook, spaceIcons: BrowserSpaceIconDisplay, settings: Set<BrowserAppearanceSetting>?) {
        self.look = look
        self.spaceIcons = spaceIcons
        self.settings = settings
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> BrowserCustomizationStyle? {
        all.first { $0.name == name }
    }

    /// The style of the setup look `look`.
    static func matching(_ look: SetupLook) -> BrowserCustomizationStyle {
        all.first { $0.look == look } ?? standard
    }

    // MARK: - Actions - Looks

    /// The look a Space wearing `branding` takes in this style: `remembered`,
    /// the look it wore when it was last in this style, or else this style's
    /// look made from its own, keeping its crest and texture. A look leaving a
    /// tinted sidebar takes its colors back from the template it started
    /// from, or else wears its one color at full strength.
    func look(for branding: SpaceBranding, remembered: SpaceBranding?) -> SpaceBranding {
        if let remembered { return remembered }
        var base = branding
        if look.tint == nil, Self.isTinted(branding) {
            if let house = SpaceHouse.startingPoint(of: branding) {
                base = house.look
                base.crest = branding.crest
                base.textureStrength = branding.textureStrength
            } else {
                base.bannerStrength = 1
                base.readabilityFade = SpaceBranding.legacyReadabilityFade
                base.keepsControlsReadable = true
                base.textColorMode = .automatic
                base.symbolColor = nil
            }
        }
        return look.applying(to: base)
    }

    /// Whether `branding` is a look worth remembering as this style's: a
    /// tinted sidebar for the tinted style, and any other look for the rest.
    /// A Space that arrives restyled from another device may wear a look of
    /// another style, which is not this one's to give back.
    func keeps(_ branding: SpaceBranding) -> Bool {
        (look.tint != nil) == Self.isTinted(branding)
    }

    /// Whether `branding` already wears this style's look, at whatever
    /// intensity and direction the person gave it.
    func wears(_ branding: SpaceBranding) -> Bool {
        let worn = branding.normalized()
        var applied = look.applying(to: worn)
        applied.bannerStrength = worn.bannerStrength
        applied.gradientAngle = worn.gradientAngle
        return applied.normalized() == worn
    }

    /// Whether `branding` wears a tinted look: one color as a gradient, with
    /// no readability fade and no controls kept readable over it, as only
    /// the tinted style leaves a sidebar. A one-color Modern gradient keeps
    /// both, so it stays Modern's.
    private static func isTinted(_ branding: SpaceBranding) -> Bool {
        branding.colors.colors.count == 1 && branding.themeMode == .gradient && branding.readabilityFade == 0
            && !branding.keepsControlsReadable
    }

    // MARK: - Actions - Settings

    /// Whether `setting` stays on the page in this style, rather than in
    /// Advanced.
    func shows(_ setting: BrowserAppearanceSetting) -> Bool {
        settings?.contains(setting) ?? true
    }
}

// MARK: - Hashable

extension BrowserCustomizationStyle {
    static func == (lhs: BrowserCustomizationStyle, rhs: BrowserCustomizationStyle) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
