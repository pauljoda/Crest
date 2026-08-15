import Foundation

extension BrowserSyncPayload {
    func validate() throws {
        switch self {
        case let .space(space):
            try validateText(space.name, limit: 128, field: "space.name")
            try validateText(space.symbol, limit: 128, field: "space.symbol")
            try validateOrderToken(space.orderToken, field: "space.orderToken")
        case let .folder(folder):
            try validateText(folder.title, limit: 512, field: "folder.title")
            try validateText(folder.symbol, limit: 128, field: "folder.symbol")
            try validateOrderToken(folder.orderToken, field: "folder.orderToken")
            if folder.parentID == folder.id {
                throw BrowserSyncError.invalidField("folder.parentID")
            }
        case let .tab(tab):
            try validateText(tab.title, limit: 2_048, field: "tab.title")
            if let customTitle = tab.customTitle {
                try validateText(customTitle, limit: 2_048, field: "tab.customTitle")
            }
            try validateText(tab.symbol, limit: 128, field: "tab.symbol")
            try validateOrderToken(tab.orderToken, field: "tab.orderToken")
            if let url = tab.url { try validateURL(url) }
            if tab.placement != .saved, tab.folderID != nil {
                throw BrowserSyncError.invalidField("tab.folderID")
            }
        case let .history(history):
            try validateURL(history.url)
            try validateText(history.title, limit: 2_048, field: "history.title")
            guard history.visitCount > 0,
                  history.firstVisitedAt <= history.lastVisitedAt else {
                throw BrowserSyncError.invalidField("history.timestamps")
            }
        case let .archive(archive):
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
              scheme == "http" || scheme == "https" else {
            throw BrowserSyncError.invalidURL(value)
        }
    }
}
