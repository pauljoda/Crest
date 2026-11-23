import SwiftUI

/// The page's extensions, from an engine that has them: a caps label with
/// Manage, which opens the Extensions page, over the engine's own tiles.
struct SiteControlsExtensionsSection<Tiles: View>: View {
    let model: SiteControlsModel
    @ViewBuilder let tiles: () -> Tiles

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SiteControlsSectionHeader(title: "Extensions") {
                Button("Manage") { model.open(.extensions) }
                    .buttonStyle(SiteControlsTextButtonStyle())
                    .accessibilityLabel("Manage Extensions")
            }
            tiles()
        }
    }
}

/// Blocking on the page's site, in its Space, as a card: whether the site
/// blocks and at which level, and the kinds of things the lists that are on
/// keep off the page, with the Space's switch for the site, which reloads the
/// page. The card opens Ads and Trackers, as the chevron on its trailing edge
/// says.
struct SiteControlsBlockingTile: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        let blocking = model.contentBlocking
        let blocks = blocking?.blocks == true
        let kinds = blocking == nil ? [] : model.blockedKinds
        let hidesElements = blocking != nil && model.blockedElements.exist
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    model.open(.blocking)
                } label: {
                    HStack(spacing: CrestSpacing.small) {
                        Image(systemName: blocks ? "checkmark.shield" : "shield.slash")
                            .font(.system(size: metrics.glyphSize * 0.75, weight: .semibold))
                            .foregroundStyle(blocks ? Color.white : .primary)
                            .frame(width: metrics.toggleSymbolSize, height: metrics.toggleSymbolSize)
                            .background(blocks ? CrestBrandTheme.accent : CrestColor.chromeSurface, in: .circle)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Ads and trackers")
                                .font(metrics.rowFont.weight(.semibold))
                            Text(detail(blocking))
                                .font(metrics.detailFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CrestSpacing.small)
                    .frame(maxWidth: .infinity, minHeight: metrics.blockingHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ads and trackers")
                .accessibilityValue(Text(accessibilityValue(blocking, kinds: kinds)))
                .accessibilityHint("Shows ads and trackers on this site")
                .accessibilityIdentifier("site-control-blocking")
                if let blocking {
                    SiteControlsSwitch(
                        title: Text(blocking.title),
                        isOn: Binding(
                            get: { blocking.blocks }, set: { _ in model.platform.run(.toggleContentBlocking) })
                    )
                    .padding(.horizontal, CrestSpacing.small)
                    .disabled(!model.platform.canRun(.toggleContentBlocking))
                    .accessibilityIdentifier("site-content-blocking-switch")
                }
                Divider()
                    .frame(height: metrics.blockingHeight * 0.55)
                Button {
                    model.open(.blocking)
                } label: {
                    CrestFormDisclosureChevron()
                        .frame(width: 26, height: metrics.blockingHeight)
                        .contentShape(.rect)
                }
                .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact))
                .accessibilityLabel("Ads and Trackers Options")
                .accessibilityIdentifier("site-control-blocking-options")
            }
            if let blocking {
                Button {
                    model.open(.blocking)
                } label: {
                    CrestFlowLayout(gap: 4) {
                        SiteControlsBlockChip(
                            title: model.blockingLevelTitle, symbol: "shield.lefthalf.filled", isActive: false)
                        ForEach(kinds, id: \.self) { kind in
                            SiteControlsBlockChip(title: kind.title, symbol: kind.symbol, isActive: blocking.blocks)
                        }
                        if hidesElements {
                            SiteControlsBlockChip(
                                title: "Hidden by you", symbol: "rectangle.dashed", isActive: blocking.blocks)
                        }
                    }
                    .padding(.horizontal, CrestSpacing.small)
                    .padding(.bottom, CrestSpacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .crestHoverSurface(cornerRadius: CrestRadius.compact, showsRestingSurface: true)
        .accessibilityElement(children: .contain)
    }

    /// Whether the site blocks, naming it by its host.
    private func detail(_ blocking: SiteContentBlockingSwitch?) -> LocalizedStringResource {
        guard let blocking else { return "This Space blocks nothing" }
        return blocking.blocks ? "Blocked on \(blocking.origin.host)" : "Allowed on \(blocking.origin.host)"
    }

    /// The card's state for VoiceOver: what it says, the level, and the kinds
    /// it blocks.
    private func accessibilityValue(_ blocking: SiteContentBlockingSwitch?, kinds: [ContentBlockKind]) -> String {
        let detail = String(localized: detail(blocking))
        guard blocking?.blocks == true, !kinds.isEmpty else { return detail }
        let level = String(localized: model.blockingLevelTitle)
        let names = kinds.map { String(localized: $0.title) }.formatted(.list(type: .and))
        return String(localized: "\(detail), \(level). Blocks \(names)")
    }
}

/// One kind of thing blocking keeps off the page, as a small chip: Crest blue
/// while the site blocks it, muted while the site allows it.
private struct SiteControlsBlockChip: View {
    let title: LocalizedStringResource
    let symbol: String
    let isActive: Bool

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(metrics.tileFont)
        .foregroundStyle(isActive ? CrestBrandTheme.accentText : .secondary)
        .padding(.horizontal, 7)
        .frame(height: metrics.chipHeight - 4)
        .background(
            isActive ? CrestBrandTheme.accent.opacity(CrestOpacity.statusFill) : CrestColor.chromeSurface, in: .capsule
        )
        .fixedSize()
    }
}

/// The toggles that change the page, each showing its state: Reader,
/// Translate with a way into its options, and on a phone the site's desktop
/// version.
struct SiteControlsPageToggles: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        let translation = model.page.translation
        let readerIsOn = model.page.readerModeState.isActive
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: metrics.toggleColumns), spacing: 6
        ) {
            SiteControlsToggleTile(
                title: "Reader", symbol: "doc.plaintext", isOn: readerIsOn,
                state: readerIsOn ? "On" : "Off", isEnabled: model.platform.canRun(.toggleReaderMode),
                identifier: "site-control-reader"
            ) { model.platform.run(.toggleReaderMode) }
            SiteControlsToggleTile(
                title: "Translate", symbol: "translate", isOn: translation.isTranslated,
                state: readerIsOn
                    ? "Off while Reader is on"
                    : translation.isTranslated ? "\(translation.languageName(translation.targetID))" : "Off",
                isEnabled: !readerIsOn && model.platform.canRun(.toggleTranslationToolbar),
                identifier: "site-control-translate", more: { model.open(.translate) }
            ) {
                if translation.isTranslated { translation.showOriginal() } else { translation.start() }
            }
            if let isOn = model.platform.requestsDesktopSite {
                SiteControlsToggleTile(
                    title: "Desktop Site", symbol: "desktopcomputer", isOn: isOn, state: isOn ? "On" : "Off",
                    isEnabled: true, identifier: "site-control-desktop-site"
                ) { model.platform.toggleDesktopSite() }
            }
        }
    }
}

/// A toggle tile: its symbol in a circle that fills Crest blue while it is
/// on, its title over its state, and an optional chevron into its options.
private struct SiteControlsToggleTile: View {
    let title: LocalizedStringResource
    let symbol: String
    let isOn: Bool
    let state: LocalizedStringResource
    let isEnabled: Bool
    let identifier: String
    var more: (() -> Void)?
    let toggle: () -> Void

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.stacksToggleTiles {
                // A finger's tile: the symbol over the title and state, as
                // the Control Center's are, with the options chevron in its
                // corner.
                ZStack(alignment: .topTrailing) {
                    toggleButton {
                        VStack(alignment: .leading, spacing: 2) {
                            symbolCircle
                            Spacer(minLength: CrestSpacing.small)
                            titles
                        }
                        .padding(CrestSpacing.small + 2)
                        .frame(maxWidth: .infinity, minHeight: metrics.toggleHeight, alignment: .leading)
                    }
                    if let more {
                        moreButton(more)
                            .frame(width: 40, height: 40)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    toggleButton {
                        HStack(spacing: CrestSpacing.small) {
                            symbolCircle
                            titles
                        }
                        .padding(.horizontal, CrestSpacing.small)
                        .frame(maxWidth: .infinity, minHeight: metrics.toggleHeight)
                    }
                    if let more {
                        Divider()
                            .frame(height: metrics.toggleHeight * 0.55)
                        moreButton(more)
                            .frame(width: 26, height: metrics.toggleHeight)
                    }
                }
            }
        }
        .opacity(isEnabled ? 1 : CrestOpacity.disabledControl + 0.13)
        .crestHoverSurface(
            isSelected: isOn, cornerRadius: CrestRadius.compact, showsRestingSurface: true)
    }

    private var symbolCircle: some View {
        Image(systemName: symbol)
            .font(.system(size: metrics.glyphSize * 0.75, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : .primary)
            .frame(width: metrics.toggleSymbolSize, height: metrics.toggleSymbolSize)
            .background(isOn ? CrestBrandTheme.accent : CrestColor.chromeSurface, in: .circle)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(metrics.rowFont.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(state)
                .font(metrics.tileFont)
                .foregroundStyle(isOn ? CrestBrandTheme.accentText : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleButton(@ViewBuilder label: () -> some View) -> some View {
        Button(action: toggle) {
            label()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(state))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func moreButton(_ more: @escaping () -> Void) -> some View {
        Button(action: more) {
            CrestFormDisclosureChevron()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact))
        .accessibilityLabel(Text("\(String(localized: title)) Options"))
        .accessibilityIdentifier("\(identifier)-options")
    }
}

/// The page's zoom: a full-width row with a stepper, whose value returns the
/// page to its actual size.
struct SiteControlsZoomRow: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        SiteControlsRowLabel(title: Text("Zoom"), symbol: "textformat.size") {
            HStack(spacing: 1) {
                stepperButton("minus", label: "Zoom Out", command: .zoomOut)
                Button {
                    model.platform.run(.actualSize)
                } label: {
                    Text(verbatim: model.zoomLabel)
                        .font(metrics.valueFont.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 50, minHeight: metrics.chipHeight - 2)
                        .contentShape(.capsule)
                }
                .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: (metrics.chipHeight - 2) / 2))
                .help("Actual Size")
                .accessibilityLabel(Text("Page zoom \(model.zoomLabel)"))
                .accessibilityHint("Returns the page to its actual size")
                stepperButton("plus", label: "Zoom In", command: .zoomIn)
            }
            .padding(.horizontal, 1)
            .background(CrestColor.chromeSurface, in: .capsule)
            .disabled(!model.canZoom)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Page Zoom")
        }
        .padding(.leading, CrestFormRowButtonStyle.reach)
        .accessibilityIdentifier("site-control-zoom")
    }

    private func stepperButton(_ symbol: String, label: LocalizedStringResource, command: ShortcutCommand) -> some View
    {
        Button {
            model.platform.run(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: metrics.glyphSize * 0.65, weight: .bold))
                .frame(width: metrics.chipHeight + 4, height: metrics.chipHeight - 2)
                .contentShape(.capsule)
        }
        .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: (metrics.chipHeight - 2) / 2))
        .disabled(!model.platform.canRun(command))
        .accessibilityLabel(Text(label))
    }
}

/// The rows that show their value and open the rest: Permissions, Opens in
/// where there is more than one engine, Site Data, Downloads and More
/// Actions.
struct SiteControlsValueRows: View {
    let model: SiteControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.origin != nil {
                SiteControlsRow(
                    "Permissions", symbol: "hand.raised", value: model.permissionSummary,
                    compactValue: model.compactPermissionSummary
                ) {
                    model.open(.permissions)
                }
                .accessibilityIdentifier("site-control-permissions")
            }
            if let engines = model.platform.engineChoice {
                SiteControlsEngineRow(choice: engines)
            }
            if model.host != nil {
                SiteControlsRow("Site Data", symbol: "externaldrive", value: nil) { model.open(.siteData) }
                    .accessibilityIdentifier("site-control-site-data")
            }
            SiteControlsRow("Downloads", symbol: "arrow.down.circle", value: model.downloadsSummary) {
                model.openDownloads()
            }
            .accessibilityIdentifier(downloadsIdentifier)
            SiteControlsRow("More Actions", symbol: "ellipsis.circle", value: "\(model.moreActions.count)") {
                model.isEditingActions = false
                model.open(.actions)
            }
            .accessibilityIdentifier("site-control-more-actions")
        }
        .padding(.horizontal, CrestFormRowButtonStyle.reach)
    }

    /// The Downloads row's identifier, the one iPhone and iPad gave the
    /// menu's Downloads item before Site Controls.
    private var downloadsIdentifier: String {
        #if os(iOS)
            BrowserMobileAccessibilityID.pageActionsDownloads
        #else
            "site-control-downloads"
        #endif
    }
}

/// Which engine the site opens in, shown while the device registered more
/// than one: a menu of the engines, each with its mark, where choosing one
/// moves the page and keeps the site there, and the one-time move.
private struct SiteControlsEngineRow: View {
    let choice: SiteControlsEngineChoice

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        SiteControlsRowLabel(title: Text("Opens in"), symbol: "arrow.triangle.swap") {
            Menu {
                Group {
                    Section("New Pages of This Site Open in") {
                        Picker(
                            "Opens in",
                            selection: Binding(
                                get: { choice.current },
                                set: { engine in
                                    guard engine != choice.current else { return }
                                    choice.remember(engine)
                                })
                        ) {
                            ForEach(choice.engines, id: \.self) { engine in
                                Label {
                                    Text(engine.title)
                                } icon: {
                                    BrowserSiteEngineMenuIcon(logo: choice.logo(engine))
                                }
                                .tag(engine)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Divider()
                    ForEach(choice.engines.filter { $0 != choice.current }, id: \.self) { engine in
                        Button(
                            "Open This Page in \(String(localized: engine.title))", systemImage: "arrow.triangle.swap"
                        ) {
                            choice.move(engine)
                        }
                    }
                }
                .crestMenuActionLabelStyle()
            } label: {
                HStack(spacing: 5) {
                    BrowserSiteEngineMenuIcon(logo: choice.logo(choice.current))
                    Text(choice.current.title)
                        .font(metrics.valueFont)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 7)
                .padding(.trailing, 5)
                .frame(height: metrics.chipHeight - 2)
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: 6))
            .fixedSize()
            .crestMenuActionLabelStyle()
            .accessibilityLabel(Text("Opens in \(choice.current.title)"))
            .accessibilityIdentifier("site-engine-picker")
        }
    }
}
