import Foundation
import Observation

@Observable
@MainActor
final class BrowserDataPortabilityModel {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    var exportDocument: BrowserPortableArchiveDocument?
    var isPreparingExport = false
    var isExporting = false
    var isImporting = false
    var bookmarkExportDocument: BrowserBookmarkHTMLDocument?
    var isPreparingBookmarkExport = false
    var isExportingBookmarks = false
    var isImportingBookmarks = false
    var bookmarkImportSource: BrowserBookmarkMigrationSource?
    var isImportingHistory = false
    var historyImportSource: BrowserHistoryMigrationSource?
    var isImportingTabs = false
    var tabImportSource: BrowserTabMigrationSource?
    var status: BrowserDataPortabilityOperationStatus?

    @ObservationIgnored
    private let operations: any BrowserDataPortabilityOperating

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        operations: any BrowserDataPortabilityOperating =
            LiveBrowserDataPortabilityOperations()
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        self.operations = operations
    }

    var lockedSpaces: [BrowserSpace] {
        BrowserSettingsPrivacyPolicy.lockedSpaces(
            in: browser.session.spaces,
            accessController: spaceAccess
        )
    }

    var lockedSpaceIDs: [SpaceID] {
        lockedSpaces.map(\.id)
    }

    func beginPortableImport() {
        isImporting = true
    }

    func beginBookmarkImport(from source: BrowserBookmarkMigrationSource) {
        bookmarkImportSource = source
        isImportingBookmarks = true
    }

    func beginHistoryImport(from source: BrowserHistoryMigrationSource) {
        historyImportSource = source
        isImportingHistory = true
    }

    func beginTabImport(from source: BrowserTabMigrationSource) {
        tabImportSource = source
        isImportingTabs = true
    }

    func prepareExport() {
        guard lockedSpaces.isEmpty else { return }
        isPreparingExport = true
        status = nil
        let session = browser.session
        Task { @MainActor in
            defer { isPreparingExport = false }
            do {
                exportDocument = try await operations.portableArchiveDocument(
                    for: session
                )
                guard lockedSpaces.isEmpty else {
                    exportDocument = nil
                    return
                }
                isExporting = true
            } catch {
                status = BrowserDataPortabilityOperationStatus(error: error)
            }
        }
    }

    func prepareBookmarkExport() {
        guard lockedSpaces.isEmpty else { return }
        isPreparingBookmarkExport = true
        status = nil
        let session = browser.session
        Task { @MainActor in
            defer { isPreparingBookmarkExport = false }
            do {
                bookmarkExportDocument = try await operations.bookmarkDocument(
                    for: session
                )
                guard lockedSpaces.isEmpty else {
                    bookmarkExportDocument = nil
                    return
                }
                isExportingBookmarks = true
            } catch {
                status = BrowserDataPortabilityOperationStatus(error: error)
            }
        }
    }

    func finishPortableExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            status = BrowserDataPortabilityOperationStatus("Browser data exported.")
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
        exportDocument = nil
    }

    func finishBookmarkExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            status = BrowserDataPortabilityOperationStatus("Bookmarks exported.")
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
        bookmarkExportDocument = nil
    }

    func finishPortableImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importArchive(from: url)
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
    }

    func finishBookmarkImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let source = bookmarkImportSource else {
                return
            }
            importBookmarks(from: url, source: source)
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
    }

    func finishHistoryImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let source = historyImportSource else {
                return
            }
            importHistory(from: url, source: source)
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
    }

    func finishTabImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let source = tabImportSource else {
                return
            }
            importTabs(from: url, source: source)
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
    }

    func cancelSensitiveExports() {
        isExporting = false
        isExportingBookmarks = false
        exportDocument = nil
        bookmarkExportDocument = nil
    }

    private func importArchive(from url: URL) {
        status = BrowserDataPortabilityOperationStatus("Reading browser data…")
        Task { @MainActor in
            do {
                let imported = try await operations.portableImport(from: url)
                try browser.importPortableArchive(imported)
                let summary = imported.summary
                status = BrowserDataPortabilityOperationStatus(
                    "Imported \(summary.spaceCount) Spaces, \(summary.liveTabCount) tabs, and \(summary.historyEntryCount) history entries."
                )
            } catch {
                status = BrowserDataPortabilityOperationStatus(error: error)
            }
        }
    }

    private func importBookmarks(
        from url: URL,
        source: BrowserBookmarkMigrationSource
    ) {
        let sourceTitle = String(localized: source.title)
        status = BrowserDataPortabilityOperationStatus(
            "Reading \(sourceTitle) bookmarks…"
        )
        Task { @MainActor in
            do {
                let imported = try await operations.bookmarkImport(
                    from: url,
                    source: source
                )
                try browser.importPortableArchive(imported)
                let summary = imported.summary
                status = BrowserDataPortabilityOperationStatus(
                    "Imported \(summary.liveTabCount) bookmarks in \(summary.spaceCount) Spaces from \(sourceTitle)."
                )
            } catch {
                status = BrowserDataPortabilityOperationStatus(error: error)
            }
        }
    }

    private func importHistory(
        from url: URL,
        source: BrowserHistoryMigrationSource
    ) {
        let sourceTitle = String(localized: source.title)
        status = BrowserDataPortabilityOperationStatus(
            "Reading \(sourceTitle) history…"
        )
        Task { @MainActor in
            do {
                let imported = try await operations.historyImport(
                    from: url,
                    source: source
                )
                try browser.importPortableArchive(imported)
                status = BrowserDataPortabilityOperationStatus(
                    "Imported \(imported.summary.historyEntryCount) history entries from \(sourceTitle)."
                )
            } catch {
                status = BrowserDataPortabilityOperationStatus(error: error)
            }
        }
    }

    private func importTabs(
        from url: URL,
        source: BrowserTabMigrationSource
    ) {
        let sourceTitle = String(localized: source.title)
        status = BrowserDataPortabilityOperationStatus(
            "Reading \(sourceTitle) tabs…"
        )
        Task { @MainActor in
            do {
                let imported = try await operations.tabImport(
                    from: url,
                    source: source
                )
                try browser.importPortableArchive(imported)
                let summary = imported.summary
                status = BrowserDataPortabilityOperationStatus(
                    "Imported \(summary.liveTabCount) tabs in \(summary.spaceCount) Spaces from \(sourceTitle)."
                )
            } catch {
                status = BrowserDataPortabilityOperationStatus(error: error)
            }
        }
    }
}
