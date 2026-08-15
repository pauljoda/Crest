import Foundation

enum BrowserDetectedImportReader {
    private static let maximumTabsPerSpace = 5_000

    static func read(
        _ payload: BrowserDetectedImportPayload,
        importedAt: Date = .now
    ) async throws -> BrowserPortableImport {
        var spaces: [BrowserSpace] = []
        var lastReadError: (any Error)?
        for profile in payload.profiles {
            if payload.application == .arc || payload.application == .zen {
                guard let sessionURL = profile.sessionURL else { continue }
                let imported = try await BrowserTabMigrationFileIO.read(
                    from: sessionURL,
                    source: payload.application.migrationSource
                )
                spaces.append(contentsOf: imported.spaces)
                continue
            }

            var combined: BrowserSpace?
            if let bookmarksURL = profile.bookmarksURL,
                let source = bookmarkSource(for: payload.application)
            {
                do {
                    let data = try await readData(from: bookmarksURL)
                    let imported = try BrowserBookmarkMigration.decode(
                        data,
                        source: source,
                        importedAt: importedAt
                    )
                    combined = imported.spaces.first
                } catch {
                    lastReadError = error
                }
            }

            if let sessionURL = profile.sessionURL {
                do {
                    let imported = try await BrowserTabMigrationFileIO.read(
                        from: sessionURL,
                        source: payload.application.migrationSource
                    )
                    combined = merge(
                        imported.spaces,
                        into: combined,
                        application: payload.application
                    )
                } catch {
                    lastReadError = error
                }
            }

            if var combined {
                combined.name = profile.name
                combined.symbol = payload.application.migrationSource.symbol
                combined.accent = payload.application.migrationSource.accent
                spaces.append(combined)
            }
        }

        guard !spaces.isEmpty else {
            throw lastReadError ?? BrowserTabMigrationError.noImportableTabs
        }
        guard spaces.count <= BrowserPortableArchive.maximumSpaceCount else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }
        return BrowserPortableImport(
            spaces: spaces,
            summary: BrowserPortableImportSummary(
                spaceCount: spaces.count,
                folderCount: spaces.reduce(0) { $0 + $1.folders.count },
                liveTabCount: spaces.reduce(0) { $0 + $1.tabs.count },
                archivedTabCount: 0,
                historyEntryCount: 0
            )
        )
    }

    private static func bookmarkSource(
        for application: BrowserImportApplication
    ) -> BrowserBookmarkMigrationSource? {
        switch application {
        case .chrome: .chromeBookmarks
        case .safari: .safariBookmarks
        case .arc: .arcSidebar
        case .firefox: .firefoxBookmarks
        case .zen: nil
        }
    }

    private static func readData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }

    private static func merge(
        _ importedSpaces: [BrowserSpace],
        into existing: BrowserSpace?,
        application: BrowserImportApplication
    ) -> BrowserSpace? {
        guard var result = existing ?? importedSpaces.first else { return nil }
        let spacesToAppend =
            existing == nil
            ? importedSpaces.dropFirst()
            : importedSpaces[...]
        for space in spacesToAppend {
            guard result.tabs.count + space.tabs.count <= maximumTabsPerSpace,
                result.folders.count + space.folders.count
                    <= BrowserSpace.maximumFolderCount
            else { continue }
            result.folders.append(contentsOf: space.folders)
            result.tabs.append(contentsOf: space.tabs)
            if let selectedTabID = space.selectedTabID {
                result.selectedTabID = selectedTabID
            }
        }
        result.symbol = application.migrationSource.symbol
        result.accent = application.migrationSource.accent
        return result
    }
}
