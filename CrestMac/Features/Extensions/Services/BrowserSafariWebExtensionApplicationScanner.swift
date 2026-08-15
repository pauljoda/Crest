import Foundation

/// Finds host applications that expose the Safari Web Extension point WebKit
/// can load. Verification and WebKit preflight deliberately remain the
/// inspector's responsibility so discovery never treats an app as installable
/// merely because its Info.plist makes the right claim.
struct BrowserSafariWebExtensionApplicationScanner {
    static var defaultSearchRoots: [URL] {
        let fileManager = FileManager.default
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    private let fileManager: FileManager
    private let locator: BrowserSafariWebExtensionAppLocator

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        locator = BrowserSafariWebExtensionAppLocator(fileManager: fileManager)
    }

    func scan(
        searchRoots: [URL] = Self.defaultSearchRoots
    ) -> [BrowserSafariWebExtensionApplicationMatch] {
        var matchesByPath: [String: BrowserSafariWebExtensionApplicationMatch] =
            [:]

        for applicationURL in applicationURLs(in: searchRoots) {
            let canonicalURL =
                applicationURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let key = canonicalURL.path
            guard matchesByPath[key] == nil,
                let descriptors = try? locator.locate(in: canonicalURL),
                !descriptors.isEmpty
            else {
                continue
            }
            matchesByPath[key] = BrowserSafariWebExtensionApplicationMatch(
                applicationURL: canonicalURL,
                applicationDisplayName:
                    descriptors[0].applicationDisplayName,
                descriptors: descriptors
            )
        }

        return matchesByPath.values.sorted { lhs, rhs in
            let ordering = lhs.applicationDisplayName.localizedStandardCompare(
                rhs.applicationDisplayName
            )
            if ordering != .orderedSame {
                return ordering == .orderedAscending
            }
            return lhs.applicationURL.path < rhs.applicationURL.path
        }
    }

    private func applicationURLs(in roots: [URL]) -> [URL] {
        var urls: [URL] = []
        for root in roots {
            if root.pathExtension.lowercased() == "app" {
                urls.append(root)
                continue
            }
            guard
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isApplicationKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                )
            else {
                continue
            }
            for case let url as URL in enumerator
            where url.pathExtension.lowercased() == "app" {
                urls.append(url)
            }
        }
        return urls
    }
}
