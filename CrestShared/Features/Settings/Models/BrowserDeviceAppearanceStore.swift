import Foundation
import Observation
import SwiftUI

// MARK: - Types

/// How tabs look on every Space on this device.
///
/// A model rather than a value, so each view tracks only the choices it draws:
/// a row that reads its border never re-renders while someone drags the hover
/// tint. ``BrowserDeviceAppearanceStore`` keeps the one instance and saves it
/// whenever a choice changes.
@MainActor @Observable
final class BrowserTabAppearance {
    enum Borders: String, Codable, CaseIterable { case selected, pinned, all }
    /// How a tab shows a status its page is in, such as playing sound: as a
    /// badge on its icon, or in place of its icon.
    enum StatusStyle: String, Codable, CaseIterable { case badge, icon }
    var borders: Borders = .selected { didSet { changed() } }
    var outlinesSelectedTabs = false { didSet { changed() } }
    var usesWebsitePinColor = true { didSet { changed() } }
    var dimsUnloadedTabs = true { didSet { changed() } }
    var pinFill: Double = 0 { didSet { changed() } }
    var pinGlow: Double = 0 { didSet { changed() } }
    var hoverFill: Double = 0 { didSet { changed() } }
    var color: BrandColor? { didSet { changed() } }
    var statusStyle: StatusStyle = .badge { didSet { changed() } }
    /// Whether a tab playing sound shows bars across it.
    var showsAudioVisualizer = true { didSet { changed() } }
    /// Called after any choice changes, so its owner can save it.
    @ObservationIgnored var changed: () -> Void = {}

    init() {}

    nonisolated static func intensity(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// The address field's look on every Space on this device, observed choice by
/// choice as ``BrowserTabAppearance`` is.
@MainActor @Observable
final class BrowserAddressAppearance {
    /// What the field shows of a page's address while it is not being edited.
    enum Display: String, Codable, CaseIterable {
        /// The site over its path, on two lines.
        case twoLines
        /// The site and its path on one line, cut short after the site.
        case oneLine
        /// The site alone.
        case siteOnly
    }
    var fill: Double = 0 { didSet { changed() } }
    var border: Double = 0 { didSet { changed() } }
    var usesAccentWhenEditing = false { didSet { changed() } }
    /// Whether the field grows into the command palette and the palette
    /// shrinks back into it, rather than the palette opening in place.
    var animatesIntoCommandPalette = true { didSet { changed() } }
    /// Whether a live site's address field offers a button that copies its
    /// URL, beside Site Controls. Only the Mac's sidebar field draws it.
    var showsCopyURLButton = false { didSet { changed() } }
    var display: Display = .twoLines { didSet { changed() } }
    var color: BrandColor? { didSet { changed() } }
    /// Called after any choice changes, so its owner can save it.
    @ObservationIgnored var changed: () -> Void = {}

    init() {}
}

extension BrowserTabAppearance: @MainActor Codable {
    private enum CodingKeys: String, CodingKey {
        case borders, outlinesSelectedTabs, usesWebsitePinColor, dimsUnloadedTabs
        case pinFill, pinGlow, hoverFill, color, statusStyle, showsAudioVisualizer
    }

    convenience init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        borders = (try? values.decode(Borders.self, forKey: .borders)) ?? .selected
        outlinesSelectedTabs = (try? values.decode(Bool.self, forKey: .outlinesSelectedTabs)) ?? false
        usesWebsitePinColor = (try? values.decode(Bool.self, forKey: .usesWebsitePinColor)) ?? true
        dimsUnloadedTabs = (try? values.decode(Bool.self, forKey: .dimsUnloadedTabs)) ?? true
        pinFill = Self.intensity((try? values.decode(Double.self, forKey: .pinFill)) ?? 0)
        pinGlow = Self.intensity((try? values.decode(Double.self, forKey: .pinGlow)) ?? 0)
        hoverFill = Self.intensity((try? values.decode(Double.self, forKey: .hoverFill)) ?? 0)
        color = try? values.decode(BrandColor.self, forKey: .color)
        statusStyle = (try? values.decode(StatusStyle.self, forKey: .statusStyle)) ?? .badge
        showsAudioVisualizer = (try? values.decode(Bool.self, forKey: .showsAudioVisualizer)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(borders, forKey: .borders)
        try values.encode(outlinesSelectedTabs, forKey: .outlinesSelectedTabs)
        try values.encode(usesWebsitePinColor, forKey: .usesWebsitePinColor)
        try values.encode(dimsUnloadedTabs, forKey: .dimsUnloadedTabs)
        try values.encode(pinFill, forKey: .pinFill)
        try values.encode(pinGlow, forKey: .pinGlow)
        try values.encode(hoverFill, forKey: .hoverFill)
        try values.encodeIfPresent(color, forKey: .color)
        try values.encode(statusStyle, forKey: .statusStyle)
        try values.encode(showsAudioVisualizer, forKey: .showsAudioVisualizer)
    }
}

extension BrowserAddressAppearance: @MainActor Codable {
    private enum CodingKeys: String, CodingKey {
        case fill, border, usesAccentWhenEditing, animatesIntoCommandPalette, showsCopyURLButton, display, color
    }

    convenience init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fill = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .fill)) ?? 0)
        border = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .border)) ?? 0)
        usesAccentWhenEditing = (try? values.decode(Bool.self, forKey: .usesAccentWhenEditing)) ?? false
        animatesIntoCommandPalette =
            (try? values.decode(Bool.self, forKey: .animatesIntoCommandPalette)) ?? true
        showsCopyURLButton = (try? values.decode(Bool.self, forKey: .showsCopyURLButton)) ?? false
        display = (try? values.decode(Display.self, forKey: .display)) ?? .twoLines
        color = try? values.decode(BrandColor.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fill, forKey: .fill)
        try values.encode(border, forKey: .border)
        try values.encode(usesAccentWhenEditing, forKey: .usesAccentWhenEditing)
        try values.encode(animatesIntoCommandPalette, forKey: .animatesIntoCommandPalette)
        try values.encode(showsCopyURLButton, forKey: .showsCopyURLButton)
        try values.encode(display, forKey: .display)
        try values.encodeIfPresent(color, forKey: .color)
    }
}

/// Local presentation preferences never enter a Space record or CloudKit payload.
/// Decode once; Observation invalidates only views reading the changed value.
///
/// Views read the choices they draw from here, never with `@AppStorage`: each
/// write to these defaults makes every `@AppStorage` view over them re-check
/// its value, and a sidebar would hold hundreds. For the same reason the store
/// keeps every choice in memory and writes them out once they settle, not on
/// every step of a drag.
@MainActor @Observable
final class BrowserDeviceAppearanceStore {
    // MARK: - Static Variables

    static let shared = BrowserDeviceAppearanceStore(
        defaults: BrowserFolderAppearancePreference.defaults, chrome: BrowserChromeAppearancePreference.defaults)
    static let tabsKey = "crest.appearance.tabs"
    static let addressKey = "crest.appearance.address"
    static let cornerRadiusKey = "crest.appearance.cornerRadius"
    static let surfaceMaterialKey = "crest.appearance.surfaceMaterial"
    static let surfaceToneKey = "crest.appearance.surfaceTone"
    static let modeKey = "crest.appearance.mode"
    static let darkSpaceDimmingKey = "crest.appearance.darkSpaceDimming"
    static let spaceIconSizingKey = "crest.appearance.spaceIconSizing"
    static let spaceIconScaleKey = "crest.appearance.spaceIconScale"
    static let sidebarRevealWidthKey = "crest.appearance.sidebar-reveal-width"
    static let sidebarRevealDelayKey = "crest.appearance.sidebar-reveal-delay"
    static let sidebarSlideDurationKey = "crest.appearance.sidebar-slide-duration"
    static let peekSizeKey = "crest.appearance.peek-size"
    static let tabHoverPreviewKey = "crest.appearance.hover-preview.tabs"
    static let folderHoverPreviewKey = "crest.appearance.hover-preview.folders"
    static let customizationStyleKey = "crest.appearance.customization-style"
    static let spaceIconsKey = "crest.appearance.space-icons"
    static let spaceCustomizationStylesKey = "crest.appearance.space-customization-styles"
    static let rememberedLooksKey = "crest.appearance.space-style-looks"
    static let maximumCornerRadius: Double = 40
    /// How long the choices stay still before the store writes them out.
    static let settleDelay = Duration.milliseconds(300)

    // MARK: - Variables

    var cornerRadius: Double {
        didSet { saveSoon() }
    }
    var sidebarCornerRadius: Double {
        cornerRadius.isFinite
            ? min(max(cornerRadius, 0), Self.maximumCornerRadius) : BrowserLookAndFeelDefaults.cornerRadius
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let chrome: UserDefaults
    /// The write waiting for the choices to settle.
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// How wide the frame around every page is, in points; zero runs pages to
    /// the window's edges.
    var windowBorderWidth: Double {
        didSet {
            isBorderless = BrowserChromeAppearance(borderWidth: windowBorderWidth).borderless
            saveSoon()
        }
    }
    /// Whether pages run to the window's edges. A view that only asks this
    /// reads it rather than the width, so a drag across the width leaves it be.
    private(set) var isBorderless: Bool
    /// Whether the sidebar stands on the window's right.
    var sidebarOnRight: Bool {
        didSet { saveSoon() }
    }
    /// How wide, in points, the strip along the window's edge is that shows a
    /// hidden sidebar when the pointer rests on it. Only the Mac has one.
    var sidebarRevealWidth: Double {
        didSet { saveSoon() }
    }
    /// How long, in milliseconds, the pointer rests on that strip before the
    /// hidden sidebar shows; zero shows it at once.
    var sidebarRevealDelay: Double {
        didSet { saveSoon() }
    }
    /// How long, in milliseconds, the sidebar takes to slide out over the
    /// page, the length every other sidebar slide is measured against; zero
    /// puts it in place at once.
    var sidebarSlideDuration: Double {
        didSet { saveSoon() }
    }
    /// How much of the room beside the sidebar a Peek's card takes, within
    /// ``BrowserTransientCardArrangement/pointerCardShares``. Only the Mac's
    /// Peek floats in that room.
    var peekSize: Double {
        didSet { saveSoon() }
    }
    /// Whether a sidebar tab or pin the pointer rests on shows its preview
    /// card, where the window draws one.
    var previewsTabsOnHover: Bool {
        didSet { saveSoon() }
    }
    /// Whether a sidebar folder the pointer rests on shows a card of its tabs.
    var previewsFoldersOnHover: Bool {
        didSet { saveSoon() }
    }
    /// How tabs look. Replaced only to reset it; otherwise its choices change
    /// in place, each observed on its own. A binding to one choice assigns the
    /// same instance back, which is no change.
    var tabs: BrowserTabAppearance {
        didSet {
            guard tabs !== oldValue else { return }
            observeChanges()
            saveSoon()
        }
    }
    /// How the address field looks, kept as ``tabs`` is.
    var address: BrowserAddressAppearance {
        didSet {
            guard address !== oldValue else { return }
            observeChanges()
            saveSoon()
        }
    }
    /// The material the sidebar's layers are drawn with, stored by name.
    var surfaceMaterial: CrestSurfaceMaterial {
        didSet { saveSoon() }
    }
    /// Whether that material, and the text on it, reads light or dark,
    /// stored by name.
    var surfaceTone: CrestSurfaceTone {
        didSet { saveSoon() }
    }
    /// Whether windows draw light, dark, or as the system does, stored by name.
    var mode: BrowserAppearanceMode {
        didSet { saveSoon() }
    }
    /// How far a dark appearance dims each Space's colors toward charcoal,
    /// from 0, as chosen, to 1.
    var darkSpaceDimming: Double {
        didSet {
            dimsSpaceColors = Self.dims(in: shownColorScheme, by: darkSpaceDimming)
            saveSoon()
        }
    }
    /// Whether the Space switcher fits its icons to the sidebar or draws them
    /// at ``spaceIconScale``, stored by name.
    var spaceIconSizing: BrowserSpaceIconSizing {
        didSet { saveSoon() }
    }
    /// The size the Space switcher draws its icons at when it does not fit
    /// them, as a fraction of their usual size.
    var spaceIconScale: Double {
        didSet { saveSoon() }
    }
    /// How much of the customization every Space shows, stored by name.
    var customizationStyle: BrowserCustomizationStyle {
        didSet { saveSoon() }
    }
    /// How the Space switcher shows Spaces as the person chose it, or nil
    /// while it follows ``customizationStyle``.
    var chosenSpaceIcons: BrowserSpaceIconDisplay? {
        didSet { saveSoon() }
    }
    /// How the Space switcher shows Spaces.
    var spaceIcons: BrowserSpaceIconDisplay { chosenSpaceIcons ?? customizationStyle.spaceIcons }
    /// The style each Space shows its own customization in where it differs
    /// from ``customizationStyle``, by Space.
    private(set) var spaceCustomizationStyles: [UUID: BrowserCustomizationStyle] {
        didSet { saveSoon() }
    }
    /// The look each Space last wore in each style, by Space and then by the
    /// style's name, so choosing a style again gives a Space back its look in
    /// it. Kept in the form the stored session keeps branding in, which every
    /// later build reads.
    @ObservationIgnored private var rememberedLooks: [UUID: [String: SpaceBranding]] {
        didSet { saveSoon() }
    }
    /// The size tabs, pins and folders are drawn at, as a fraction of their
    /// usual size.
    var tabScale: Double {
        didSet { saveSoon() }
    }
    /// How much room the sidebar keeps between its rows, bars and sections,
    /// stored by name.
    var sidebarSpacing: BrowserSidebarSpacing {
        didSet { saveSoon() }
    }
    /// How many pins a row holds at most; zero balances the rows.
    var pinColumns: Int {
        didSet { saveSoon() }
    }
    /// Whether a short last row of pins stretches across the sidebar instead
    /// of leaving empty cells.
    var pinsFillRow: Bool {
        didSet { saveSoon() }
    }
    /// Whether folders keep their highlight when the pointer is elsewhere and
    /// none of their tabs is selected.
    var foldersAlwaysVisible: Bool {
        didSet { saveSoon() }
    }
    /// Whether folder headers show how many tabs they hold.
    var foldersShowTabCounts: Bool {
        didSet { saveSoon() }
    }
    /// Whether folders draw a border in their color.
    var foldersShowBorders: Bool {
        didSet { saveSoon() }
    }
    /// Whether a folder with a custom icon or emoji shows it in place of the
    /// folder artwork.
    var foldersIconOnly: Bool {
        didSet { saveSoon() }
    }
    /// Whether folder titles take the folder's color.
    var foldersTintTitle: Bool {
        didSet { saveSoon() }
    }
    /// The scheme the windows draw in now, as the platform reports it once
    /// ``mode`` and the system's own appearance are applied.
    var shownColorScheme = ColorScheme.light {
        didSet { dimsSpaceColors = Self.dims(in: shownColorScheme, by: darkSpaceDimming) }
    }
    /// Whether the windows dim Space colors now, as a dark scheme with some
    /// dimming does. A view that only asks this tracks it rather than the
    /// dimming, so a drag of the dimming leaves it be.
    private(set) var dimsSpaceColors = false

    // MARK: - Initializers

    /// A store over `defaults`, which keeps the window's frame and sidebar
    /// side in `chrome` where those live apart from the rest.
    init(defaults: UserDefaults, chrome: UserDefaults? = nil) {
        self.defaults = defaults
        let chrome = chrome ?? defaults
        self.chrome = chrome
        let borderWidth =
            chrome.object(forKey: BrowserChromeAppearancePreference.borderWidthKey) as? Double
            ?? BrowserLookAndFeelDefaults.windowBorderWidth
        windowBorderWidth = borderWidth
        isBorderless = BrowserChromeAppearance(borderWidth: borderWidth).borderless
        sidebarOnRight = chrome.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
        sidebarRevealWidth =
            chrome.object(forKey: Self.sidebarRevealWidthKey) as? Double
            ?? Double(BrowserCollapsedSidebarRevealMetrics.pointer.width)
        sidebarRevealDelay =
            chrome.object(forKey: Self.sidebarRevealDelayKey) as? Double
            ?? BrowserLookAndFeelDefaults.sidebarRevealDelay
        sidebarSlideDuration =
            chrome.object(forKey: Self.sidebarSlideDurationKey) as? Double
            ?? BrowserLookAndFeelDefaults.sidebarSlideDuration
        previewsTabsOnHover =
            defaults.object(forKey: Self.tabHoverPreviewKey) as? Bool ?? BrowserLookAndFeelDefaults.previewsTabsOnHover
        previewsFoldersOnHover =
            defaults.object(forKey: Self.folderHoverPreviewKey) as? Bool
            ?? BrowserLookAndFeelDefaults.previewsFoldersOnHover
        let shares = BrowserTransientCardArrangement.pointerCardShares
        peekSize =
            (defaults.object(forKey: Self.peekSizeKey) as? Double).flatMap {
                $0.isFinite ? min(max($0, shares.lowerBound), shares.upperBound) : nil
            } ?? shares.upperBound
        if defaults.object(forKey: Self.cornerRadiusKey) != nil {
            cornerRadius = defaults.double(forKey: Self.cornerRadiusKey)
        } else {
            let legacy =
                defaults.data(forKey: Self.tabsKey).flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }?["cornerRadius"] as? Double
            let migratedRadius =
                legacy == 24 ? Self.maximumCornerRadius : (legacy ?? BrowserLookAndFeelDefaults.cornerRadius)
            cornerRadius = migratedRadius
            defaults.set(
                migratedRadius.isFinite
                    ? min(max(migratedRadius, 0), Self.maximumCornerRadius) : BrowserLookAndFeelDefaults.cornerRadius,
                forKey: Self.cornerRadiusKey)
        }
        tabs =
            defaults.data(forKey: Self.tabsKey).flatMap {
                try? JSONDecoder().decode(BrowserTabAppearance.self, from: $0)
            } ?? .init()
        address =
            defaults.data(forKey: Self.addressKey).flatMap {
                try? JSONDecoder().decode(BrowserAddressAppearance.self, from: $0)
            } ?? .init()
        surfaceMaterial =
            CrestSurfaceMaterial.named(defaults.string(forKey: Self.surfaceMaterialKey))
            ?? BrowserLookAndFeelDefaults.surfaceMaterial
        surfaceTone =
            CrestSurfaceTone.named(defaults.string(forKey: Self.surfaceToneKey))
            ?? BrowserLookAndFeelDefaults.surfaceTone
        mode =
            BrowserAppearanceMode.named(defaults.string(forKey: Self.modeKey))
            ?? BrowserLookAndFeelDefaults.appearanceMode
        darkSpaceDimming =
            (defaults.object(forKey: Self.darkSpaceDimmingKey) as? Double).flatMap {
                $0.isFinite ? min(max($0, 0), 1) : nil
            } ?? BrowserLookAndFeelDefaults.darkSpaceDimming
        spaceIconSizing =
            BrowserSpaceIconSizing.named(defaults.string(forKey: Self.spaceIconSizingKey))
            ?? BrowserLookAndFeelDefaults.spaceIconSizing
        spaceIconScale =
            (defaults.object(forKey: Self.spaceIconScaleKey) as? Double).map {
                Double(BrowserSpaceIconSizing.clamped($0))
            } ?? BrowserLookAndFeelDefaults.spaceIconScale
        customizationStyle =
            BrowserCustomizationStyle.named(defaults.string(forKey: Self.customizationStyleKey))
            ?? BrowserLookAndFeelDefaults.customizationStyle
        chosenSpaceIcons = BrowserSpaceIconDisplay.named(defaults.string(forKey: Self.spaceIconsKey))
        spaceCustomizationStyles =
            (defaults.dictionary(forKey: Self.spaceCustomizationStylesKey) as? [String: String] ?? [:])
            .reduce(into: [:]) { styles, entry in
                guard let space = UUID(uuidString: entry.key), let style = BrowserCustomizationStyle.named(entry.value)
                else { return }
                styles[space] = style
            }
        rememberedLooks = Self.rememberedLooks(in: defaults)
        tabScale =
            (defaults.object(forKey: BrowserSidebarDensityPreference.scaleKey) as? Double).flatMap {
                $0.isFinite ? BrowserSidebarDensity.stepped($0) : nil
            } ?? BrowserLookAndFeelDefaults.tabScale
        sidebarSpacing =
            BrowserSidebarSpacing.named(defaults.string(forKey: BrowserSidebarDensityPreference.spacingKey))
            ?? BrowserLookAndFeelDefaults.sidebarSpacing
        pinColumns =
            defaults.object(forKey: BrowserSidebarDensityPreference.pinColumnsKey) as? Int
            ?? BrowserLookAndFeelDefaults.pinColumns
        pinsFillRow =
            defaults.object(forKey: BrowserSidebarDensityPreference.pinsFillRowKey) as? Bool
            ?? BrowserLookAndFeelDefaults.pinsFillRow
        foldersAlwaysVisible =
            defaults.object(forKey: BrowserFolderAppearancePreference.alwaysVisibleKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersAlwaysVisible
        foldersShowTabCounts =
            defaults.object(forKey: BrowserFolderAppearancePreference.showsTabCountsKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersShowTabCounts
        foldersShowBorders =
            defaults.object(forKey: BrowserFolderAppearancePreference.showsBordersKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersShowBorders
        foldersIconOnly =
            defaults.object(forKey: BrowserFolderAppearancePreference.iconOnlyKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersIconOnly
        foldersTintTitle =
            defaults.object(forKey: BrowserFolderAppearancePreference.tintsTitleKey) as? Bool
            ?? BrowserLookAndFeelDefaults.foldersTintTitle
        dimsSpaceColors = Self.dims(in: shownColorScheme, by: darkSpaceDimming)
        observeChanges()
        // A choice made just before the app quits or steps aside, or leaves
        // for the background where it may never come back, is written at once.
        for notification in Self.leavingNotifications {
            NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.saveNow() }
            }
        }
    }

    // MARK: - Actions - Customization Styles

    /// The style `spaceID` shows its customization in: its own, or else
    /// ``customizationStyle``.
    func customizationStyle(for spaceID: UUID) -> BrowserCustomizationStyle {
        spaceCustomizationStyles[spaceID] ?? customizationStyle
    }

    /// Whether `spaceID` shows its customization in a style of its own.
    func hasOwnCustomizationStyle(_ spaceID: UUID) -> Bool {
        spaceCustomizationStyles[spaceID] != nil
    }

    /// Gives `spaceID` `style` for its customization, or has it follow
    /// ``customizationStyle`` again when `style` is nil or that same style.
    func setCustomizationStyle(_ style: BrowserCustomizationStyle?, for spaceID: UUID) {
        spaceCustomizationStyles[spaceID] = style == customizationStyle ? nil : style
    }

    /// The look `spaceID`, wearing `branding`, takes on moving from
    /// `previous` to `style`: the look it wore in `style` before, or else that
    /// style's look made from its own. The look it leaves is kept for when it
    /// comes back, when it is a look of `previous` at all.
    func look(
        of spaceID: UUID, wearing branding: SpaceBranding, movingFrom previous: BrowserCustomizationStyle,
        to style: BrowserCustomizationStyle
    ) -> SpaceBranding {
        guard previous != style else { return branding }
        if previous.keeps(branding) { remember(branding, of: spaceID, in: previous) }
        return style.look(for: branding, remembered: rememberedLook(of: spaceID, in: style))
    }

    /// The look `spaceID` wore when it was last in `style`, if it has been.
    private func rememberedLook(of spaceID: UUID, in style: BrowserCustomizationStyle) -> SpaceBranding? {
        rememberedLooks[spaceID]?[style.name]
    }

    /// Keeps `branding` as the look `spaceID` wears in `style`.
    private func remember(_ branding: SpaceBranding, of spaceID: UUID, in style: BrowserCustomizationStyle) {
        rememberedLooks[spaceID, default: [:]][style.name] = branding
    }

    /// The looks `defaults` keeps, each read back by the core.
    private static func rememberedLooks(in defaults: UserDefaults) -> [UUID: [String: SpaceBranding]] {
        let stored = defaults.dictionary(forKey: rememberedLooksKey) as? [String: [String: String]] ?? [:]
        return stored.reduce(into: [:]) { looks, entry in
            guard let space = UUID(uuidString: entry.key) else { return }
            looks[space] = entry.value.compactMapValues { (try? CrestCore.answer(RestoreLook(text: $0)))?.look }
        }
    }

    // MARK: - Actions - Space Colors

    /// Whether a window in `colorScheme` dims Space colors `dimming` of the way.
    private static func dims(in colorScheme: ColorScheme, by dimming: Double) -> Bool {
        colorScheme == .dark && dimming > 0
    }

    // MARK: - Actions - Saving

    /// Writes every choice that changed now, rather than once they settle.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        write(sidebarCornerRadius, forKey: Self.cornerRadiusKey, in: defaults)
        write(try? JSONEncoder().encode(tabs), forKey: Self.tabsKey, in: defaults)
        write(try? JSONEncoder().encode(address), forKey: Self.addressKey, in: defaults)
        write(surfaceMaterial.name, forKey: Self.surfaceMaterialKey, in: defaults)
        write(surfaceTone.name, forKey: Self.surfaceToneKey, in: defaults)
        write(mode.name, forKey: Self.modeKey, in: defaults)
        write(darkSpaceDimming, forKey: Self.darkSpaceDimmingKey, in: defaults)
        write(spaceIconSizing.name, forKey: Self.spaceIconSizingKey, in: defaults)
        write(spaceIconScale, forKey: Self.spaceIconScaleKey, in: defaults)
        write(customizationStyle.name, forKey: Self.customizationStyleKey, in: defaults)
        if let chosenSpaceIcons {
            write(chosenSpaceIcons.name, forKey: Self.spaceIconsKey, in: defaults)
        } else if defaults.object(forKey: Self.spaceIconsKey) != nil {
            defaults.removeObject(forKey: Self.spaceIconsKey)
        }
        let spaceStyles = spaceCustomizationStyles.reduce(into: [String: String]()) {
            $0[$1.key.uuidString] = $1.value.name
        }
        write(spaceStyles as NSDictionary, forKey: Self.spaceCustomizationStylesKey, in: defaults)
        let looks = rememberedLooks.reduce(into: [String: [String: String]]()) { looks, entry in
            looks[entry.key.uuidString] = entry.value.compactMapValues {
                (try? CrestCore.answer(StoreLook(look: $0)))?.text
            }
        }
        write(looks as NSDictionary, forKey: Self.rememberedLooksKey, in: defaults)
        write(tabScale, forKey: BrowserSidebarDensityPreference.scaleKey, in: defaults)
        write(sidebarSpacing.name, forKey: BrowserSidebarDensityPreference.spacingKey, in: defaults)
        write(peekSize, forKey: Self.peekSizeKey, in: defaults)
        write(previewsTabsOnHover, forKey: Self.tabHoverPreviewKey, in: defaults)
        write(previewsFoldersOnHover, forKey: Self.folderHoverPreviewKey, in: defaults)
        write(pinColumns, forKey: BrowserSidebarDensityPreference.pinColumnsKey, in: defaults)
        write(pinsFillRow, forKey: BrowserSidebarDensityPreference.pinsFillRowKey, in: defaults)
        write(foldersAlwaysVisible, forKey: BrowserFolderAppearancePreference.alwaysVisibleKey, in: defaults)
        write(foldersShowTabCounts, forKey: BrowserFolderAppearancePreference.showsTabCountsKey, in: defaults)
        write(foldersShowBorders, forKey: BrowserFolderAppearancePreference.showsBordersKey, in: defaults)
        write(foldersIconOnly, forKey: BrowserFolderAppearancePreference.iconOnlyKey, in: defaults)
        write(foldersTintTitle, forKey: BrowserFolderAppearancePreference.tintsTitleKey, in: defaults)
        write(windowBorderWidth, forKey: BrowserChromeAppearancePreference.borderWidthKey, in: chrome)
        write(sidebarOnRight, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey, in: chrome)
        write(sidebarRevealWidth, forKey: Self.sidebarRevealWidthKey, in: chrome)
        write(sidebarRevealDelay, forKey: Self.sidebarRevealDelayKey, in: chrome)
        write(sidebarSlideDuration, forKey: Self.sidebarSlideDurationKey, in: chrome)
    }

    /// Writes the choices once they have stayed still for ``settleDelay``.
    private func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes `value` unless the defaults hold it already, so a write that
    /// changes nothing never makes their `@AppStorage` views re-check.
    private func write(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        guard let value, (defaults.object(forKey: key) as? NSObject)?.isEqual(value) != true else { return }
        defaults.set(value, forKey: key)
    }

    /// Saves the tab and address appearance once a choice in one of them
    /// changes.
    private func observeChanges() {
        tabs.changed = { [weak self] in self?.saveSoon() }
        address.changed = { [weak self] in self?.saveSoon() }
    }

    #if os(macOS)
        private static var leavingNotifications: [Notification.Name] {
            [NSApplication.willTerminateNotification, NSApplication.didResignActiveNotification]
        }
    #else
        private static var leavingNotifications: [Notification.Name] { [UIApplication.didEnterBackgroundNotification] }
    #endif
}
