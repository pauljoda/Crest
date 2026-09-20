import Foundation

enum BrowserSyncProjection {
    static func payloads(
        from session: BrowserSession,
        preferences: BrowserSyncPreferences,
        existingRecords: [BrowserSyncRecord]
    ) throws -> [BrowserSyncPayload] {
        #if CREST_CORE_BACKED
        return try BrowserCoreSync.project(session, preferences: preferences, records: existingRecords)
        #else
        var payloads: [BrowserSyncPayload] = []
        let existingTokens = existingOrderTokens(from: existingRecords)
        let spaceRecordIDs = session.spaces.map {
            BrowserSyncRecordID(kind: .space, value: $0.id.rawValue)
        }
        let spaceTokens = try BrowserSyncOrderTokenAllocator.allocate(
            ids: spaceRecordIDs,
            existingTokens: existingTokens
        )

        for (space, spaceRecordID) in zip(session.spaces, spaceRecordIDs) {
            let includedTabs = space.tabs.filter { tab in
                BrowserSyncContentPolicy.includes(tab)
                    && (tab.placement == .current ? preferences.currentTabs : preferences.savedStructure)
            }
            let includedSplitIDs = Set(
                space.tabs.filter { BrowserSyncContentPolicy.includes($0) }.compactMap(\.splitGroupID))
            payloads.append(
                .space(
                    BrowserSyncSpace(
                        id: space.id,
                        profileID: space.profile.id,
                        name: space.name,
                        symbol: space.symbol,
                        accent: space.accent,
                        branding: space.branding,
                        browsingPreferences: space.browsingPreferences,
                        accessPolicy: space.accessPolicy,
                        isSavedTabsExpanded: space.isSavedTabsExpanded,
                        savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt,
                        splitGroups: space.splitGroups.filter { includedSplitIDs.contains($0.id) },
                        orderToken: try requiredOrderToken(
                            for: spaceRecordID,
                            in: spaceTokens
                        )
                    )))

            if preferences.savedStructure || preferences.currentTabs {
                let folderTree = BrowserFolderTree(
                    folders: space.folders.filter {
                        $0.location == .current ? preferences.currentTabs : preferences.savedStructure
                    })
                guard folderTree.isValid else {
                    throw BrowserSyncError.invalidFolderHierarchy(space.id)
                }

                var folderTokens: [BrowserSyncRecordID: String] = [:]
                var parentIDs: [FolderID?] = [nil]
                parentIDs.append(
                    contentsOf: folderTree.foldersInDisplayOrder.map {
                        Optional($0.id)
                    })
                for parentID in parentIDs {
                    let siblingRecordIDs = folderTree.children(of: parentID).map {
                        BrowserSyncRecordID(kind: .folder, value: $0.id.rawValue)
                    }
                    folderTokens.merge(
                        try BrowserSyncOrderTokenAllocator.allocate(
                            ids: siblingRecordIDs,
                            existingTokens: existingTokens
                        ),
                        uniquingKeysWith: { _, latest in latest }
                    )
                }

                for folder in folderTree.foldersInDisplayOrder {
                    let recordID = BrowserSyncRecordID(
                        kind: .folder,
                        value: folder.id.rawValue
                    )
                    payloads.append(
                        .folder(
                            BrowserSyncFolder(
                                id: folder.id,
                                spaceID: space.id,
                                title: folder.title,
                                location: folder.location,
                                symbol: folder.symbol,
                                color: folder.color,
                                parentID: folder.parentID,
                                isCollapsed: folder.isCollapsed,
                                collapseModifiedAt: folder.collapseModifiedAt,
                                orderAnchorTabID: folder.orderAnchorTabID,
                                orderToken: try requiredOrderToken(
                                    for: recordID,
                                    in: folderTokens
                                )
                            )))
                }
            }

            let tabRecordIDs = includedTabs.map {
                BrowserSyncRecordID(kind: .tab, value: $0.id.rawValue)
            }
            let tabTokens = try BrowserSyncOrderTokenAllocator.allocate(
                ids: tabRecordIDs,
                existingTokens: existingTokens
            )
            for (tab, recordID) in zip(includedTabs, tabRecordIDs) {
                payloads.append(
                    .tab(
                        BrowserSyncTab(
                            id: tab.id,
                            spaceID: space.id,
                            title: tab.title,
                            url: tab.url,
                            nativeContent: tab.nativeContent,
                            savedURL: tab.savedSiteURL,
                            symbol: tab.symbol,
                            placement: tab.placement,
                            folderID: tab.folderID,
                            splitGroupID: tab.splitGroupID,
                            orderToken: try requiredOrderToken(
                                for: recordID,
                                in: tabTokens
                            ),
                            lastActivatedAt: tab.lastActivatedAt,
                            positionModifiedAt: tab.positionModifiedAt,
                            customTitle: tab.customTitle,
                            titleModifiedAt: tab.titleModifiedAt,
                            keepsPageLoaded: tab.keepsPageLoaded
                        )))
            }

            if preferences.historyAndArchive {
                for history in space.history where BrowserSyncContentPolicy.includes(history.url) {
                    payloads.append(
                        .history(
                            BrowserSyncHistory(
                                id: history.id,
                                spaceID: space.id,
                                url: history.url,
                                title: history.title,
                                firstVisitedAt: history.firstVisitedAt,
                                lastVisitedAt: history.lastVisitedAt,
                                visitCount: history.visitCount
                            )))
                }
                let includedArchive = space.archivedTabs.filter { BrowserSyncContentPolicy.includes($0.tab) }
                let archiveRecordIDs = includedArchive.map {
                    BrowserSyncRecordID(kind: .archive, value: $0.id.rawValue)
                }
                let archiveTokens = try BrowserSyncOrderTokenAllocator.allocate(
                    ids: archiveRecordIDs,
                    existingTokens: existingTokens
                )
                for (archive, recordID) in zip(
                    includedArchive,
                    archiveRecordIDs
                ) {
                    payloads.append(
                        .archive(
                            BrowserSyncArchive(
                                tab: BrowserSyncTab(
                                    id: archive.tab.id,
                                    spaceID: space.id,
                                    title: archive.tab.title,
                                    url: archive.tab.url,
                                    nativeContent: archive.tab.nativeContent,
                                    symbol: archive.tab.symbol,
                                    placement: .current,
                                    folderID: nil,
                                    // No `splitGroupID`: archiving a tab takes
                                    // it out of its split everywhere.
                                    orderToken: try requiredOrderToken(
                                        for: recordID,
                                        in: archiveTokens
                                    ),
                                    lastActivatedAt: archive.tab.lastActivatedAt,
                                    positionModifiedAt: archive.tab.positionModifiedAt,
                                    customTitle: archive.tab.customTitle,
                                    titleModifiedAt: archive.tab.titleModifiedAt,
                                    keepsPageLoaded: archive.tab.keepsPageLoaded
                                ),
                                archivedAt: archive.archivedAt,
                                reason: archive.reason.syncProjectionReason
                            )))
                }
            }
        }

        for payload in payloads {
            try payload.validate()
        }
        return payloads
        #endif
    }

    private static func requiredOrderToken(
        for recordID: BrowserSyncRecordID,
        in tokens: [BrowserSyncRecordID: String]
    ) throws -> String {
        guard let token = tokens[recordID] else {
            throw BrowserSyncError.invalidRecord(recordID.recordName)
        }
        return token
    }

    private static func existingOrderTokens(
        from records: [BrowserSyncRecord]
    ) -> [BrowserSyncRecordID: String] {
        Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                switch record.payload {
                case .space(let space):
                    (record.id, space.orderToken)
                case .folder(let folder):
                    (record.id, folder.orderToken)
                case .tab(let tab):
                    (record.id, tab.orderToken)
                case .archive(let archive):
                    (record.id, archive.tab.orderToken)
                case .history, .none:
                    nil
                }
            })
    }
}

/// Only portable web pages enter sync. Native documents and device-specific
/// schemes remain in the local session, including when remote changes arrive.
enum BrowserSyncContentPolicy {
    static func includes(_ url: URL?) -> Bool {
        guard let url, let host = url.host, !host.isEmpty else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    static func includes(_ tab: BrowserTab) -> Bool {
        tab.nativeContent == nil && includes(tab.url)
            && (tab.savedSiteURL == nil || includes(tab.savedSiteURL))
    }

    static func includes(_ tab: BrowserSyncTab) -> Bool {
        tab.nativeContent == nil && includes(tab.url)
            && (tab.savedURL == nil || includes(tab.savedURL))
    }

    static func includes(_ payload: BrowserSyncPayload) -> Bool {
        switch payload {
        case .space, .folder: true
        case .tab(let tab): includes(tab)
        case .archive(let archive): includes(archive.tab)
        case .history(let history): includes(history.url)
        }
    }
}
