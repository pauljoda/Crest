import Foundation

// TRANSITIONAL until S6.7 deletes the Swift session copy, and this file with
// it. The copy (`BrowserCoreSessionAuthority.projection`) is written only
// here: each session change the core publishes for the copy's workspace is
// applied by the rules its record documents, and the core's records are read
// into the copy's types the way the decoder reads the core's stored form.
// Image bytes never reach the core: `FaviconAssets` keeps them and applies
// each change's image rules first, so every tab the copy builds or re-images
// wears the image `FaviconAssets` holds for it.

// MARK: - Applying changes

extension BrowserSession {
    /// Applies one change of this session's workspace, whose image rules
    /// `images` has already applied.
    @MainActor
    mutating func apply(_ change: Change, images: FaviconAssets) {
        let image: (UUID) -> Data? = { images.image(of: $0) }
        switch change {
        case .workspaceOpened(let opened):
            self = BrowserSession(core: opened.session, image: image)
        case .workspaceChanged(let changed):
            defaultSpaceID = changed.defaultSpaceID.map(SpaceID.init(rawValue:))
            disposableSeedMarker = changed.isDisposableSeed ? disposableSeedMarker ?? UUID() : nil
            spaceDeletions =
                changed.spaceDeletions.isEmpty
                ? nil : changed.spaceDeletions.map(BrowserSpaceDeletionIntent.init(core:))
        case .appPreferencesChanged(let changed):
            appPreferences = changed.preferences.map(BrowserAppPreferences.init(core:))
        case .spacesChanged(let changed):
            let removed = Set(changed.removed)
            spaces.removeAll { removed.contains($0.id.rawValue) }
            for state in changed.added {
                Self.upsert(BrowserSpace(core: state, image: image), into: &spaces, id: \.id.rawValue)
            }
            spaces = Self.ordered(spaces, by: changed.order, id: \.id.rawValue)
        case .spaceSettingsChanged(let changed):
            edit(changed.spaceID) { $0.configure(core: changed.settings) }
        case .tabsChanged(let changed):
            edit(changed.spaceID) { space in
                space.tabs = Self.rows(
                    space.tabs, updated: changed.updated, removed: changed.removed, order: changed.order,
                    id: \.id.rawValue, stateID: \.id
                ) { BrowserTab(core: $0, faviconData: image($0.id)) }
            }
        case .foldersChanged(let changed):
            edit(changed.spaceID) { space in
                space.folders = Self.rows(
                    space.folders, updated: changed.updated, removed: changed.removed, order: changed.order,
                    id: \.id.rawValue, stateID: \.id, make: BrowserFolder.init(core:))
            }
        case .splitGroupsChanged(let changed):
            edit(changed.spaceID) { space in
                space.splitGroups = BrowserSplitGroupMetadata.normalized(
                    changed.groups.map(BrowserSplitGroupMetadata.init(core:)))
            }
        case .archiveChanged(let changed):
            edit(changed.spaceID) { space in
                space.archivedTabs = Self.rows(
                    space.archivedTabs, updated: changed.archived, removed: changed.removed, order: changed.order,
                    id: \.id.rawValue, stateID: \.tab.id
                ) {
                    ArchivedTab(
                        tab: BrowserTab(core: $0.tab, faviconData: image($0.tab.id)), archivedAt: $0.archivedAt,
                        reason: $0.reason)
                }
            }
        case .historyChanged(let changed):
            edit(changed.spaceID) { space in
                space.history = Self.history(
                    space.history, recorded: changed.recorded, removed: changed.removed, order: changed.order)
            }
        case .tabCopied(let copied):
            setImage(image(copied.copyTabID), of: copied.copyTabID)
        case .tabsImported(let imported):
            for tab in imported.tabs { setImage(image(tab.tabID), of: tab.tabID) }
        case .tabFaviconAssigned(let assigned):
            setImage(image(assigned.tabID), of: assigned.tabID)
        default:
            break
        }
    }

    /// The tab, open or archived, wears `data`.
    private mutating func setImage(_ data: Data?, of tabID: UUID) {
        for spaceIndex in spaces.indices {
            if let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id.rawValue == tabID }) {
                spaces[spaceIndex].tabs[tabIndex].faviconData = data
                return
            }
            if let archiveIndex = spaces[spaceIndex].archivedTabs.firstIndex(where: { $0.tab.id.rawValue == tabID }) {
                spaces[spaceIndex].archivedTabs[archiveIndex].tab.faviconData = data
                return
            }
        }
    }

    private mutating func edit(_ spaceID: UUID, _ change: (inout BrowserSpace) -> Void) {
        guard let index = spaces.firstIndex(where: { $0.id.rawValue == spaceID }) else { return }
        change(&spaces[index])
    }

    /// A list after one change: the removed rows gone, each updated row in
    /// place of the row with its identity or after the others when it is new,
    /// then the order the change names, when it names one.
    private static func rows<Row, State>(
        _ rows: [Row], updated: [State], removed: [UUID], order: [UUID]?, id: KeyPath<Row, UUID>,
        stateID: KeyPath<State, UUID>, make: (State) -> Row
    ) -> [Row] {
        let gone = Set(removed)
        var result = rows.filter { !gone.contains($0[keyPath: id]) }
        for state in updated {
            if let index = result.firstIndex(where: { $0[keyPath: id] == state[keyPath: stateID] }) {
                result[index] = make(state)
            } else {
                result.append(make(state))
            }
        }
        return ordered(result, by: order, id: id)
    }

    /// A newest-first history after one change: the removed and recorded
    /// entries gone, then the recorded entries before every other, in order.
    private static func history(
        _ entries: [BrowserHistoryEntry], recorded: [HistoryEntryState], removed: [UUID], order: [UUID]?
    ) -> [BrowserHistoryEntry] {
        let gone = Set(removed).union(recorded.map(\.id))
        let front = recorded.compactMap(BrowserHistoryEntry.init(core:))
        return ordered(front + entries.filter { !gone.contains($0.id) }, by: order, id: \.id)
    }

    private static func upsert<Row>(_ row: Row, into rows: inout [Row], id: KeyPath<Row, UUID>) {
        if let index = rows.firstIndex(where: { $0[keyPath: id] == row[keyPath: id] }) {
            rows[index] = row
        } else {
            rows.append(row)
        }
    }

    private static func ordered<Row>(_ rows: [Row], by order: [UUID]?, id: KeyPath<Row, UUID>) -> [Row] {
        guard let order else { return rows }
        let byID = Dictionary(rows.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }
    }
}

// MARK: - Offering images

extension FaviconAssets.Offer {
    /// The images every tab and archived tab of the sessions wears.
    init(placedFrom session: BrowserSession, _ others: BrowserSession...) {
        self.init()
        for session in [session] + others {
            for space in session.spaces {
                for tab in space.tabs { placed[tab.id.rawValue] = tab.faviconData }
                for archived in space.archivedTabs { placed[archived.id.rawValue] = archived.tab.faviconData }
            }
        }
    }
}

extension FaviconAssets.Offer {
    /// The images every tab and archived tab of the imported `spaces` wears,
    /// by each Space's position.
    init(importing spaces: [BrowserSpace]) {
        self.init()
        imported = spaces.map { space in
            var images: [UUID: Data] = [:]
            for tab in space.tabs { images[tab.id.rawValue] = tab.faviconData }
            for archived in space.archivedTabs { images[archived.id.rawValue] = archived.tab.faviconData }
            return images
        }
    }
}

// MARK: - Imports

extension BrowserSpace {
    /// `spaces` as an import carries them to the core: the stored format, a
    /// JSON array, without the images the core never sees.
    static func storedFormat(_ spaces: [BrowserSpace]) throws -> Data {
        let compacted = spaces.isEmpty ? [] : BrowserCoreSessionAuthority.compact(BrowserSession(spaces: spaces)).spaces
        return try JSONEncoder().encode(compacted)
    }
}

extension BrowserImportSpaceCustomization {
    /// The name and look a Space takes, as the core reads them. The core
    /// resolves a blank name or symbol and keeps the look within the ranges
    /// every device draws.
    var core: SpaceCustomization {
        SpaceCustomization(name: name, symbol: symbol, accent: accent, branding: branding.core)
    }
}

extension ImportReviewSpace {
    /// A Space as the review of an import reads it.
    init(_ space: BrowserSpace) {
        self.init(
            id: space.id.rawValue, name: space.name,
            tabs: space.tabs.map {
                ImportReviewTab(id: $0.id.rawValue, url: $0.url?.absoluteString, placement: $0.placement)
            })
    }
}

extension BrowserSession {
    /// The session an import would leave, as `preview` answers it: each tab
    /// it would place from `sources` wears the image its source tab wears
    /// there, each of the workspace's own tabs the image `images` holds for
    /// it, or for the tab it would be a new identity of.
    @MainActor
    init(preview: ImportedWorkspace, sources: [BrowserSpace], images: FaviconAssets) {
        var placed: [UUID: Data] = [:]
        let offered = FaviconAssets.Offer(importing: sources).imported
        for tab in preview.imported where offered.indices.contains(tab.source) {
            placed[tab.tabID] = offered[tab.source][tab.sourceTabID]
        }
        var copies: [UUID: UUID] = [:]
        for copy in preview.copied { copies[copy.copyTabID] = copy.sourceTabID }
        let imported = Set(preview.imported.map(\.tabID))
        self.init(core: preview.session) { tabID in
            if imported.contains(tabID) { return placed[tabID] }
            return images.image(of: copies[tabID] ?? tabID)
        }
    }
}

// MARK: - Reading records

extension BrowserSession {
    /// The session the core published, wearing the images `image` finds by tab.
    init(core state: SessionState, image: (UUID) -> Data?) {
        self.init(
            spaces: state.spaces.map { BrowserSpace(core: $0, image: image) },
            defaultSpaceID: state.defaultSpaceID.map(SpaceID.init(rawValue:)),
            disposableSeedMarker: state.disposableSeedMarker,
            spaceDeletions: state.spaceDeletions.isEmpty
                ? nil : state.spaceDeletions.map(BrowserSpaceDeletionIntent.init(core:)),
            appPreferences: state.appPreferences.map(BrowserAppPreferences.init(core:)))
    }
}

extension BrowserSpaceDeletionIntent {
    init(core deletion: SpaceDeletionState) {
        self.init(spaceID: SpaceID(rawValue: deletion.spaceID), profileID: deletion.profileID, operationID: deletion.id)
    }
}

extension BrowserSpace {
    init(core state: SpaceState, image: (UUID) -> Data?) {
        self.init(
            id: SpaceID(rawValue: state.id), profile: BrowsingProfile(id: state.profileID), name: state.settings.name,
            symbol: state.settings.symbol, accent: state.settings.accent,
            folders: state.folders.map(BrowserFolder.init(core:)),
            tabs: state.tabs.map { BrowserTab(core: $0, faviconData: image($0.id)) },
            splitGroups: state.splitGroups.map(BrowserSplitGroupMetadata.init(core:)),
            archivedTabs: state.archivedTabs.map {
                ArchivedTab(
                    tab: BrowserTab(core: $0.tab, faviconData: image($0.tab.id)), archivedAt: $0.archivedAt,
                    reason: $0.reason)
            },
            history: state.history.compactMap(BrowserHistoryEntry.init(core:)))
        configure(core: state.settings)
    }

    /// Takes the settings the core published, as the decoder reads them: a
    /// Space without branding wears the look its accent and symbol give it,
    /// and an access policy this build cannot name asks for authentication.
    mutating func configure(core settings: SpaceSettings) {
        name = settings.name
        symbol = settings.symbol
        accent = settings.accent
        branding =
            settings.branding.map(BrowserSpaceBranding.init(core:))
            ?? .legacy(accent: settings.accent, symbol: settings.symbol)
        browsingPreferences = BrowserSpaceBrowsingPreferences(core: settings.browsingPreferences)
        credentialPreferences = BrowserCredentialPreferences(
            isEnabled: settings.credentialPreferences.isEnabled,
            syncsCrestPasswordsWithICloud: settings.credentialPreferences.syncsCrestPasswordsWithICloud,
            alsoOffersSaveToSystemPasswords: settings.credentialPreferences.alsoOffersSaveToSystemPasswords)
        accessPolicy = BrowserSpaceAccessPolicy(coreTerm: settings.accessPolicy) ?? .deviceOwnerAuthentication
        isSavedTabsExpanded = settings.isSavedTabsExpanded
        savedTabsExpansionModifiedAt = settings.savedTabsExpansionModifiedAt
    }
}

extension BrowserFolder {
    init(core state: FolderState) {
        self.init(
            id: FolderID(rawValue: state.id), title: state.title,
            location: BrowserFolderLocation(rawValue: state.location.name) ?? .saved, symbol: state.symbol ?? "folder",
            color: state.color.map(BrowserSpaceBrandColor.init(core:)) ?? .folderDefault,
            parentID: state.parentID.map(FolderID.init(rawValue:)), isCollapsed: state.isCollapsed,
            collapseModifiedAt: state.collapseModifiedAt,
            orderAnchorTabID: state.orderAnchorTabID.map(TabID.init(rawValue:)))
    }
}

extension BrowserSplitGroupMetadata {
    init(core state: SplitGroupState) {
        self.init(
            id: SplitGroupID(rawValue: state.id), customTitle: state.customTitle,
            titleModifiedAt: state.titleModifiedAt,
            customIconSymbol: state.customIconSymbol, iconModifiedAt: state.iconModifiedAt,
            tint: state.tint.map(BrowserSpaceBrandColor.init(core:)), tintModifiedAt: state.tintModifiedAt)
    }
}

extension BrowserHistoryEntry {
    /// An entry the core keeps, or nil for an address the copy cannot read,
    /// which the decoder would refuse.
    init?(core state: HistoryEntryState) {
        guard let url = URL(string: state.url) else { return nil }
        self.init(
            id: state.id, url: url, title: state.title, firstVisitedAt: state.firstVisitedAt,
            lastVisitedAt: state.lastVisitedAt, visitCount: state.visitCount)
    }
}

extension BrowserAppPreferences {
    init(core preferences: AppPreferences) {
        self.init()
        translationRules = BrowserAutomaticTranslationRules(core: preferences.translationRules)
        startupBehavior = BrowserStartupBehavior(coreTerm: preferences.startup) ?? Self.defaults.startupBehavior
        savedTabClosePolicy =
            BrowserDurableTabClosePolicy(coreTerm: preferences.savedTabClose) ?? Self.defaults.savedTabClosePolicy
        offersTranslation = preferences.offersTranslation
        automaticallyTranslates = preferences.automaticallyTranslates
        checksSpelling = preferences.checksSpelling
        automaticallyEntersPictureInPicture = preferences.automaticallyEntersPictureInPicture
        savedTabFaviconReturnsToSavedURL = preferences.savedTabFaviconReturnsToSavedURL
        splitFocusFollowsMouse = preferences.splitFocusFollowsMouse
    }
}

extension BrowserSpaceBrandColor {
    init(core color: BrandColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension BrowserSpaceBranding {
    /// Branding as the decoder reads it: strengths stored before the baseline
    /// vocabulary take today's units.
    init(core branding: SpaceBranding) {
        self.init(
            colors: branding.colors.colors.map(BrowserSpaceBrandColor.init(core:)),
            bannerPattern: BrowserSpaceBannerPattern(coreTerm: branding.bannerPattern) ?? .solid,
            bannerStrength: branding.renderingVersion >= Self.baselineRenderingVersion
                ? branding.bannerStrength : min(1, 0.72 + branding.bannerStrength * 0.28),
            readabilityFade: branding.readabilityFade,
            themeMode: BrowserSpaceThemeMode(coreTerm: branding.themeMode) ?? .banner,
            gradientAngle: branding.gradientAngle, showsTexture: branding.showsTexture,
            iconStyle: BrowserSpaceIconStyle(coreTerm: branding.iconStyle) ?? .simpleSymbol,
            symbolColor: branding.symbolColor.map(BrowserSpaceBrandColor.init(core:)),
            crest: BrowserSpaceCrest(core: branding.crest), folderColorIntensity: branding.folderColorIntensity,
            textColorMode: BrowserSpaceTextColorMode(coreTerm: branding.textColorMode) ?? .automatic,
            hasCustomAppearance: branding.hasCustomAppearance)
    }
}

extension BrowserSpaceCrest {
    init(core crest: SpaceCrest) {
        self.init(
            backplate: BrowserSpaceCrestBackplate(coreTerm: crest.backplate) ?? .shield,
            fieldDivision: BrowserSpaceCrestFieldDivision(coreTerm: crest.fieldDivision) ?? .plain,
            ordinary: BrowserSpaceCrestOrdinary(coreTerm: crest.ordinary) ?? BrowserSpaceCrestOrdinary.none,
            trim: BrowserSpaceCrestTrim(coreTerm: crest.trim) ?? BrowserSpaceCrestTrim.none,
            symbol: BrowserSpaceCrestSymbol(coreTerm: crest.symbol) ?? .fallback,
            chargeLayout: BrowserSpaceCrestChargeLayout(coreTerm: crest.chargeLayout) ?? .single,
            backplateColorIndex: crest.backplateColorIndex, secondaryFieldColorIndex: crest.secondaryFieldColorIndex,
            ordinaryColorIndex: crest.ordinaryColorIndex, trimColorIndex: crest.trimColorIndex,
            symbolColorIndex: crest.symbolColorIndex, edgeColorIndex: crest.edgeColorIndex,
            palette: crest.palette.map { $0.colors.map(BrowserSpaceBrandColor.init(core:)) },
            charge: crest.charge.map(BrowserSpaceCrestCharge.init(core:)), plateScale: crest.plateScale,
            edgeWidth: crest.edgeWidth, divisionCount: crest.divisionCount,
            finish: BrowserSpaceCrestFinish(coreTerm: crest.finish) ?? .flat, ordinaryWidth: crest.ordinaryWidth,
            trimWeight: crest.trimWeight, trimDetail: crest.trimDetail, chargeScale: crest.chargeScale,
            chargeOffset: crest.chargeOffset,
            chargeWeight: BrowserSpaceCrestChargeWeight(coreTerm: crest.chargeWeight) ?? .bold,
            startingPresetID: crest.startingPresetID, sheenAngle: crest.sheenAngle, sealTeeth: crest.sealTeeth,
            showsOutline: crest.showsOutline,
            depth: BrowserSpaceCrestDepth(coreTerm: crest.depth) ?? BrowserSpaceCrestDepth.none)
    }
}

extension BrowserSpaceCrestCharge {
    init(core charge: CrestCharge) {
        self =
            switch charge.kind {
            case .heraldic: .heraldic(charge.symbol.flatMap { BrowserSpaceCrestSymbol(coreTerm: $0) } ?? .fallback)
            case .system: .system(charge.text ?? "")
            case .emoji: .emoji(charge.text ?? "")
            case .monogram:
                .monogram(
                    charge.text ?? "", charge.style.flatMap { BrowserSpaceCrestMonogramStyle(coreTerm: $0) } ?? .serif)
            case .none: BrowserSpaceCrestCharge.none
            }
    }
}

extension RawRepresentable where RawValue == String {
    /// The copy's term for a term of the core's vocabulary. The copy's
    /// vocabularies spell each term as its stored spelling, and the generated
    /// enums name each case by that same spelling.
    init?(coreTerm term: some Sendable) {
        self.init(rawValue: String(describing: term))
    }
}

// MARK: - Sending the copy's values

extension CaseIterable {
    /// The core's term for a term of the copy's vocabulary, which spells it
    /// as the core names it; nil for one the core has no name for.
    init?(copyTerm term: some RawRepresentable<String>) {
        guard let match = Self.allCases.first(where: { String(describing: $0) == term.rawValue }) else { return nil }
        self = match
    }
}

extension BrowserSpaceBranding {
    /// This branding as a Space intent carries it, in today's units.
    var core: SpaceBranding {
        SpaceBranding(
            colors: ColorPalette(colors: colors.map(\.core)),
            bannerPattern: SpaceBannerPattern(copyTerm: bannerPattern) ?? .solid, bannerStrength: bannerStrength,
            readabilityFade: readabilityFade, keepsControlsReadable: keepsControlsReadable,
            themeMode: SpaceThemeMode(copyTerm: themeMode) ?? .banner, gradientAngle: gradientAngle,
            showsTexture: showsTexture, iconStyle: SpaceIconStyle(copyTerm: iconStyle) ?? .simpleSymbol,
            symbolColor: symbolColor?.core, crest: crest.core, renderingVersion: renderingVersion,
            folderColorIntensity: folderColorIntensity,
            textColorMode: SpaceTextColorMode(copyTerm: textColorMode) ?? .automatic,
            hasCustomAppearance: hasCustomAppearance)
    }
}

extension BrowserSpaceCrest {
    var core: SpaceCrest {
        SpaceCrest(
            backplate: CrestBackplate(copyTerm: backplate) ?? .shield,
            fieldDivision: CrestFieldDivision(copyTerm: fieldDivision) ?? .plain,
            ordinary: CrestOrdinary(copyTerm: ordinary) ?? CrestOrdinary.none,
            trim: CrestTrim(copyTerm: trim) ?? CrestTrim.none, symbol: CrestSymbol(copyTerm: symbol) ?? .mountain,
            chargeLayout: CrestChargeLayout(copyTerm: chargeLayout) ?? .single,
            backplateColorIndex: backplateColorIndex, secondaryFieldColorIndex: secondaryFieldColorIndex,
            ordinaryColorIndex: ordinaryColorIndex, trimColorIndex: trimColorIndex, symbolColorIndex: symbolColorIndex,
            startingPresetID: startingPresetID, edgeColorIndex: edgeColorIndex,
            palette: palette.map { ColorPalette(colors: $0.map(\.core)) }, charge: charge?.core, plateScale: plateScale,
            edgeWidth: edgeWidth, divisionCount: divisionCount, finish: CrestFinish(copyTerm: finish) ?? .flat,
            ordinaryWidth: ordinaryWidth, trimWeight: trimWeight, trimDetail: trimDetail, chargeScale: chargeScale,
            chargeOffset: chargeOffset, chargeWeight: CrestChargeWeight(copyTerm: chargeWeight) ?? .bold,
            sheenAngle: sheenAngle, sealTeeth: sealTeeth, showsOutline: showsOutline,
            depth: CrestDepth(copyTerm: depth) ?? CrestDepth.none)
    }
}

extension BrowserSpaceCrestCharge {
    var core: CrestCharge {
        switch self {
        case .heraldic(let symbol):
            CrestCharge(kind: .heraldic, symbol: CrestSymbol(copyTerm: symbol), text: nil, style: nil)
        case .system(let name): CrestCharge(kind: .system, symbol: nil, text: name, style: nil)
        case .emoji(let emoji): CrestCharge(kind: .emoji, symbol: nil, text: emoji, style: nil)
        case .monogram(let letters, let style):
            CrestCharge(kind: .monogram, symbol: nil, text: letters, style: CrestMonogramStyle(copyTerm: style))
        case .none: CrestCharge(kind: .none, symbol: nil, text: nil, style: nil)
        }
    }
}

extension BrowserSpaceDataRetentionPreferences {
    var core: DataRetentionPreferences {
        DataRetentionPreferences(history: history, archive: archive, downloads: downloads)
    }
}

extension BrowserCredentialPreferences {
    var core: CredentialPreferences {
        CredentialPreferences(
            isEnabled: isEnabled, syncsCrestPasswordsWithICloud: syncsCrestPasswordsWithICloud,
            alsoOffersSaveToSystemPasswords: alsoOffersSaveToSystemPasswords)
    }
}

extension BrowserAppPreferences {
    /// These preferences as the core's record carries them.
    var core: AppPreferences {
        AppPreferences(
            startup: StartupBehavior(copyTerm: startupBehavior) ?? .showStartPage,
            offersTranslation: offersTranslation, automaticallyTranslates: automaticallyTranslates,
            translationRules: translationRules.sources.keys.sorted().compactMap { source in
                translationRules.sources[source].map {
                    TranslationRule(sourceLanguage: source, targetID: $0.targetID, isEnabled: $0.isEnabled)
                }
            },
            checksSpelling: checksSpelling, automaticallyEntersPictureInPicture: automaticallyEntersPictureInPicture,
            savedTabClose: SavedTabClosePolicy(copyTerm: savedTabClosePolicy) ?? .resumeLastLocation,
            savedTabFaviconReturnsToSavedURL: savedTabFaviconReturnsToSavedURL,
            splitFocusFollowsMouse: splitFocusFollowsMouse)
    }
}
