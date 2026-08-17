import Foundation

enum BrowserSyncProjection {
    static func payloads(
        from session: BrowserSession,
        preferences: BrowserSyncPreferences,
        existingRecords: [BrowserSyncRecord]
    ) throws -> [BrowserSyncPayload] {
        var payloads: [BrowserSyncPayload] = []
        let existingTokens = existingOrderTokens(from: existingRecords)
        let spaceRecordIDs = session.spaces.map {
            BrowserSyncRecordID(kind: .space, value: $0.id.rawValue)
        }
        let spaceTokens = BrowserSyncOrderTokenAllocator.allocate(
            ids: spaceRecordIDs,
            existingTokens: existingTokens
        )

        for (space, spaceRecordID) in zip(session.spaces, spaceRecordIDs) {
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
                        orderToken: try requiredOrderToken(
                            for: spaceRecordID,
                            in: spaceTokens
                        )
                    )))

            if preferences.savedStructure {
                let folderTree = space.folderTree
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
                        BrowserSyncOrderTokenAllocator.allocate(
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
                                symbol: folder.symbol,
                                color: folder.color,
                                parentID: folder.parentID,
                                isCollapsed: folder.isCollapsed,
                                collapseModifiedAt: folder.collapseModifiedAt,
                                orderToken: try requiredOrderToken(
                                    for: recordID,
                                    in: folderTokens
                                )
                            )))
                }
            }

            let includedTabs = space.tabs.filter { tab in
                tab.placement == .current
                    ? preferences.currentTabs
                    : preferences.savedStructure
            }
            let tabRecordIDs = includedTabs.map {
                BrowserSyncRecordID(kind: .tab, value: $0.id.rawValue)
            }
            let tabTokens = BrowserSyncOrderTokenAllocator.allocate(
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
                for history in space.history {
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
                let archiveRecordIDs = space.archivedTabs.map {
                    BrowserSyncRecordID(kind: .archive, value: $0.id.rawValue)
                }
                let archiveTokens = BrowserSyncOrderTokenAllocator.allocate(
                    ids: archiveRecordIDs,
                    existingTokens: existingTokens
                )
                for (archive, recordID) in zip(
                    space.archivedTabs,
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
