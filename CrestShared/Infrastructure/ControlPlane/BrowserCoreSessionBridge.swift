import Foundation

// TRANSITIONAL until S6.1 replaces the Swift session copy with the generated
// read model, which deletes this file. The copy (`BrowserCoreSessionAuthority
// .projection`) is written only here: each session change the core publishes
// for the copy's workspace is applied by the rules its record documents, and
// the core's records are read into the copy's types the way the decoder reads
// the core's stored form. Image bytes never reach the core, so a tab keeps the
// bytes the copy holds for its identity.

// MARK: - Applying changes

extension BrowserSession {
    /// Applies one change of this session's workspace. A tab keeps the image
    /// the copy holds for it; the images of tabs a change removes join
    /// `detached`, where a later change of the same batch, in this workspace
    /// or another, finds them when it places the tab again; a tab the copy
    /// never held wears the image its command's issuer `offered`.
    mutating func apply(
        _ change: Change, detached: inout [UUID: Data], offered: BrowserCoreSessionAuthority.OfferedImages
    ) {
        let before = self
        let pending = detached
        let image: (UUID) -> Data? = { before.image(of: $0) ?? pending[$0] ?? offered.placed[$0] }
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
            for space in spaces where removed.contains(space.id.rawValue) {
                for tab in space.tabs { Self.detach(tab, into: &detached) }
                for archived in space.archivedTabs { Self.detach(archived.tab, into: &detached) }
            }
            spaces.removeAll { removed.contains($0.id.rawValue) }
            let placed = detached
            for state in changed.added {
                let space = BrowserSpace(core: state) { before.image(of: $0) ?? placed[$0] ?? offered.placed[$0] }
                Self.upsert(space, into: &spaces, id: \.id.rawValue)
            }
            spaces = Self.ordered(spaces, by: changed.order, id: \.id.rawValue)
        case .spaceSettingsChanged(let changed):
            edit(changed.spaceID) { $0.configure(core: changed.settings) }
        case .tabsChanged(let changed):
            edit(changed.spaceID) { space in
                space.tabs = Self.rows(
                    space.tabs, updated: changed.updated, removed: changed.removed, order: changed.order,
                    id: \.id.rawValue, stateID: \.id, detach: { Self.detach($0, into: &detached) }
                ) { state, existing in
                    BrowserTab(core: state, faviconData: existing.map(\.faviconData) ?? image(state.id))
                }
            }
        case .foldersChanged(let changed):
            edit(changed.spaceID) { space in
                space.folders = Self.rows(
                    space.folders, updated: changed.updated, removed: changed.removed, order: changed.order,
                    id: \.id.rawValue, stateID: \.id, detach: { _ in }
                ) { state, _ in BrowserFolder(core: state) }
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
                    id: \.id.rawValue, stateID: \.tab.id, detach: { Self.detach($0.tab, into: &detached) }
                ) { state, existing in
                    ArchivedTab(
                        tab: BrowserTab(
                            core: state.tab, faviconData: existing.map(\.tab.faviconData) ?? image(state.tab.id)),
                        archivedAt: state.archivedAt, reason: state.reason)
                }
            }
        case .historyChanged(let changed):
            edit(changed.spaceID) { space in
                space.history = Self.history(
                    space.history, recorded: changed.recorded, removed: changed.removed, order: changed.order)
            }
        case .tabCopied(let copied):
            setImage(image(copied.sourceTabID), of: copied.copyTabID)
        case .tabFaviconAssigned(let assigned):
            // A tab that adopts an image wears the one its command's issuer
            // offered, and keeps the one it wears when none is on offer.
            if !assigned.adopts {
                setImage(nil, of: assigned.tabID)
            } else if let data = offered.assigned {
                setImage(data, of: assigned.tabID)
            }
        default:
            break
        }
    }

    /// The image the copy holds for a tab or archived tab, or nil when it
    /// holds none or no tab has that identity.
    fileprivate func image(of tabID: UUID) -> Data? {
        for space in spaces {
            if let tab = space.tabs.first(where: { $0.id.rawValue == tabID }) { return tab.faviconData }
            if let archived = space.archivedTabs.first(where: { $0.id.rawValue == tabID }) {
                return archived.tab.faviconData
            }
        }
        return nil
    }

    private mutating func setImage(_ data: Data?, of tabID: UUID) {
        for spaceIndex in spaces.indices {
            guard let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id.rawValue == tabID }) else {
                continue
            }
            spaces[spaceIndex].tabs[tabIndex].faviconData = data
            return
        }
    }

    private mutating func edit(_ spaceID: UUID, _ change: (inout BrowserSpace) -> Void) {
        guard let index = spaces.firstIndex(where: { $0.id.rawValue == spaceID }) else { return }
        change(&spaces[index])
    }

    private static func detach(_ tab: BrowserTab, into detached: inout [UUID: Data]) {
        if let data = tab.faviconData { detached[tab.id.rawValue] = data }
    }

    /// A list after one change: the removed rows gone, each updated row in
    /// place of the row with its identity or after the others when it is new,
    /// then the order the change names, when it names one.
    private static func rows<Row, State>(
        _ rows: [Row], updated: [State], removed: [UUID], order: [UUID]?, id: KeyPath<Row, UUID>,
        stateID: KeyPath<State, UUID>, detach: (Row) -> Void, make: (State, Row?) -> Row
    ) -> [Row] {
        let gone = Set(removed)
        var result: [Row] = []
        result.reserveCapacity(rows.count + updated.count)
        for row in rows {
            if gone.contains(row[keyPath: id]) { detach(row) } else { result.append(row) }
        }
        for state in updated {
            if let index = result.firstIndex(where: { $0[keyPath: id] == state[keyPath: stateID] }) {
                result[index] = make(state, result[index])
            } else {
                result.append(make(state, nil))
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
