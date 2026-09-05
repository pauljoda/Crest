import Foundation

extension BrowserSyncPayload {
    func validate() throws {
        switch self {
        case .space(let space):
            try validateText(space.name, limit: 128, field: "space.name")
            try validateText(space.symbol, limit: 128, field: "space.symbol")
            if let splitGroups = space.splitGroups {
                guard splitGroups.count <= ArchiveLimits.maximumLiveTabsPerSpace,
                    Set(splitGroups.map(\.id)).count == splitGroups.count
                else {
                    throw BrowserSyncError.invalidField("space.splitGroups")
                }
                for group in splitGroups {
                    if let customTitle = group.customTitle {
                        try validateText(
                            customTitle,
                            limit: 2_048,
                            field: "splitGroup.customTitle"
                        )
                    }
                    if let customIconSymbol = group.customIconSymbol {
                        try validateText(
                            customIconSymbol,
                            limit: 128,
                            field: "splitGroup.customIconSymbol"
                        )
                        guard BrowserIconSymbol.emoji(from: customIconSymbol) != nil
                        else {
                            throw BrowserSyncError.invalidField(
                                "splitGroup.customIconSymbol"
                            )
                        }
                    }
                    try validateDate(
                        group.titleModifiedAt,
                        field: "splitGroup.titleModifiedAt"
                    )
                    try validateDate(
                        group.iconModifiedAt,
                        field: "splitGroup.iconModifiedAt"
                    )
                    try validateDate(
                        group.tintModifiedAt,
                        field: "splitGroup.tintModifiedAt"
                    )
                }
            }
            try validateOrderToken(space.orderToken, field: "space.orderToken")
        case .folder(let folder):
            try validateText(folder.title, limit: 512, field: "folder.title")
            try validateText(folder.symbol, limit: 128, field: "folder.symbol")
            try validateOrderToken(folder.orderToken, field: "folder.orderToken")
            if folder.parentID == folder.id {
                throw BrowserSyncError.invalidField("folder.parentID")
            }
        case .tab(let tab):
            try validateText(tab.title, limit: 2_048, field: "tab.title")
            if let customTitle = tab.customTitle {
                try validateText(customTitle, limit: 2_048, field: "tab.customTitle")
            }
            try validateText(tab.symbol, limit: 128, field: "tab.symbol")
            try validateOrderToken(tab.orderToken, field: "tab.orderToken")
            if let url = tab.url { try validateURL(url) }
            if tab.placement == .pinned, tab.folderID != nil {
                throw BrowserSyncError.invalidField("tab.folderID")
            }
        case .history(let history):
            try validateURL(history.url)
            try validateText(history.title, limit: 2_048, field: "history.title")
            guard history.visitCount > 0,
                history.firstVisitedAt <= history.lastVisitedAt
            else {
                throw BrowserSyncError.invalidField("history.timestamps")
            }
        case .archive(let archive):
            // Membership is the only split-group rule a lone record can carry:
            // an archived tab has left its split, exactly as it has left its
            // folder. Group size, contiguity, and uniformity are properties of
            // a run of sibling tabs that no single record can see, so
            // `BrowserSplitGroupNormalizer` owns those during runtime repair.
            try BrowserSyncPayload.tab(archive.tab).validate()
            guard archive.tab.placement == .current, archive.tab.folderID == nil, archive.tab.splitGroupID == nil else {
                throw BrowserSyncError.invalidField("archive.tab")
            }
        }
    }

    private func validateOrderToken(_ value: String, field: String) throws {
        guard BrowserSyncOrderTokenAllocator.isValidEncodedToken(value) else {
            throw BrowserSyncError.invalidField(field)
        }
    }

    private func validateText(_ value: String, limit: Int, field: String) throws {
        guard !value.isEmpty, value.utf8.count <= limit else {
            throw BrowserSyncError.invalidField(field)
        }
    }

    private func validateURL(_ url: URL) throws {
        let value = url.absoluteString
        guard value.utf8.count <= 8_192,
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            throw BrowserSyncError.invalidURL(value)
        }
    }

    private func validateDate(_ date: Date?, field: String) throws {
        guard date?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw BrowserSyncError.invalidField(field)
        }
    }
}
