import Foundation

enum BrowserImportDataLocator {
    static var hostHomeDirectory: URL {
        let fileManager = FileManager.default
        let userName = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        return resolvedHomeDirectory(
            currentHome: fileManager.homeDirectoryForCurrentUser,
            accountHome: fileManager.homeDirectory(forUser: userName)
        )
    }

    static func resolvedHomeDirectory(
        currentHome: URL,
        accountHome: URL?
    ) -> URL {
        accountHome ?? currentHome
    }

    static func importProfiles(
        for application: BrowserImportApplication,
        homeDirectory: URL = hostHomeDirectory,
        fileManager: FileManager = .default
    ) -> [BrowserDetectedImportProfile] {
        importProfiles(
            for: application,
            dataDirectory: defaultDataDirectory(
                for: application,
                homeDirectory: homeDirectory
            ),
            fileManager: fileManager
        )
    }

    static func passwordStores(
        for application: BrowserImportApplication,
        homeDirectory: URL = hostHomeDirectory,
        fileManager: FileManager = .default
    ) -> [BrowserDetectedPasswordStore] {
        passwordStores(
            for: application,
            dataDirectory: defaultDataDirectory(
                for: application,
                homeDirectory: homeDirectory
            ),
            fileManager: fileManager
        )
    }

    static func passwordStores(
        for application: BrowserImportApplication,
        dataDirectory: URL,
        fileManager: FileManager = .default
    ) -> [BrowserDetectedPasswordStore] {
        let chromiumRoot: URL
        switch application {
        case .arc:
            chromiumRoot = dataDirectory.appendingPathComponent(
                "User Data",
                isDirectory: true
            )
        case .chrome:
            chromiumRoot = dataDirectory
        case .zen, .safari, .firefox:
            return []
        }

        let displayNames = chromiumProfileDisplayNames(
            at: chromiumRoot.appendingPathComponent("Local State"),
            fileManager: fileManager
        )
        return profileDirectories(below: chromiumRoot, fileManager: fileManager)
            .filter {
                let name = $0.lastPathComponent
                return name == "Default" || name.hasPrefix("Profile ")
            }
            .sorted {
                chromiumProfileOrder($0.lastPathComponent, $1.lastPathComponent)
            }
            .compactMap { directory in
                guard
                    let databaseURL = existingFile(
                        directory.appendingPathComponent("Login Data"),
                        fileManager: fileManager
                    )
                else { return nil }
                let id = directory.lastPathComponent
                return BrowserDetectedPasswordStore(
                    id: id,
                    profileName: displayNames[id]
                        ?? (id == "Default" ? "Personal" : id),
                    databaseURL: databaseURL
                )
            }
    }

    static func importProfiles(
        for application: BrowserImportApplication,
        dataDirectory: URL,
        fileManager: FileManager = .default
    ) -> [BrowserDetectedImportProfile] {
        switch application {
        case .arc:
            let sessionURL = existingFile(
                dataDirectory.appendingPathComponent("StorableSidebar.json"),
                fileManager: fileManager
            )
            return sessionURL.map {
                [
                    BrowserDetectedImportProfile(
                        id: "arc",
                        name: "Arc",
                        bookmarksURL: nil,
                        sessionURL: $0
                    )
                ]
            } ?? []

        case .zen:
            guard
                let sessionURL = newestMatchingFile(
                    below: dataDirectory,
                    names: ["zen-sessions.jsonlz4"],
                    fileManager: fileManager
                )
            else { return [] }
            return [
                BrowserDetectedImportProfile(
                    id: sessionURL.deletingLastPathComponent().lastPathComponent,
                    name: "Zen",
                    bookmarksURL: nil,
                    sessionURL: sessionURL
                )
            ]

        case .chrome:
            return chromiumProfiles(
                below: dataDirectory,
                fileManager: fileManager
            )

        case .safari:
            return safariProfile(in: dataDirectory, fileManager: fileManager)
                .map { [$0] } ?? []

        case .firefox:
            return profileDirectories(
                below: dataDirectory,
                fileManager: fileManager
            ).compactMap {
                directory in
                guard
                    let sessionURL = newestMatchingFile(
                        below: directory,
                        names: ["recovery.jsonlz4", "sessionstore.jsonlz4"],
                        fileManager: fileManager
                    )
                else { return nil }
                return BrowserDetectedImportProfile(
                    id: directory.lastPathComponent,
                    name: directory.lastPathComponent,
                    bookmarksURL: nil,
                    sessionURL: sessionURL
                )
            }
        }
    }

    static func latestImportURL(
        for application: BrowserImportApplication,
        homeDirectory: URL = hostHomeDirectory,
        fileManager: FileManager = .default
    ) -> URL? {
        let dataDirectory = defaultDataDirectory(
            for: application,
            homeDirectory: homeDirectory
        )
        switch application {
        case .arc:
            return existingFile(
                dataDirectory.appendingPathComponent("StorableSidebar.json"),
                fileManager: fileManager
            )
        case .zen:
            return newestMatchingFile(
                below: dataDirectory,
                names: ["zen-sessions.jsonlz4"],
                fileManager: fileManager
            )
        case .chrome:
            return newestMatchingFile(
                below: dataDirectory,
                names: ["Current Session", "Current Tabs"],
                prefixes: ["Session_", "Tabs_"],
                fileManager: fileManager
            )
        case .safari:
            return existingFile(
                dataDirectory.appendingPathComponent("LastSession.plist"),
                fileManager: fileManager
            )
        case .firefox:
            return newestMatchingFile(
                below: dataDirectory,
                names: ["recovery.jsonlz4"],
                fileManager: fileManager
            )
        }
    }

    static func defaultDataDirectory(
        for application: BrowserImportApplication,
        homeDirectory: URL = hostHomeDirectory
    ) -> URL {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        switch application {
        case .arc:
            return library.appendingPathComponent(
                "Application Support/Arc",
                isDirectory: true
            )
        case .zen:
            return library.appendingPathComponent(
                "Application Support/zen/Profiles",
                isDirectory: true
            )
        case .chrome:
            return library.appendingPathComponent(
                "Application Support/Google/Chrome",
                isDirectory: true
            )
        case .safari:
            return library.appendingPathComponent("Safari", isDirectory: true)
        case .firefox:
            return library.appendingPathComponent(
                "Application Support/Firefox/Profiles",
                isDirectory: true
            )
        }
    }

    static func safariProfile(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> BrowserDetectedImportProfile? {
        let bookmarksURL = existingFile(
            directory.appendingPathComponent("Bookmarks.plist"),
            fileManager: fileManager
        )
        let sessionURL = existingFile(
            directory.appendingPathComponent("LastSession.plist"),
            fileManager: fileManager
        )
        guard bookmarksURL != nil || sessionURL != nil else { return nil }
        return BrowserDetectedImportProfile(
            id: "safari",
            name: "Safari",
            bookmarksURL: bookmarksURL,
            sessionURL: sessionURL
        )
    }

    private static func existingFile(
        _ url: URL,
        fileManager: FileManager
    ) -> URL? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { return nil }
        return url
    }

    private static func chromiumProfiles(
        below root: URL,
        fileManager: FileManager
    ) -> [BrowserDetectedImportProfile] {
        let displayNames = chromiumProfileDisplayNames(
            at: root.appendingPathComponent("Local State"),
            fileManager: fileManager
        )
        var directories = Set(displayNames.keys)
        for directory in profileDirectories(below: root, fileManager: fileManager) {
            let name = directory.lastPathComponent
            if name == "Default" || name.hasPrefix("Profile ") {
                directories.insert(name)
            }
        }
        return directories.sorted(by: chromiumProfileOrder).compactMap { directoryName in
            let directory = root.appendingPathComponent(directoryName, isDirectory: true)
            let bookmarksURL = existingFile(
                directory.appendingPathComponent("Bookmarks"),
                fileManager: fileManager
            )
            let sessionURL = newestMatchingFile(
                below: directory.appendingPathComponent("Sessions", isDirectory: true),
                names: ["Current Session", "Current Tabs"],
                prefixes: ["Session_", "Tabs_"],
                fileManager: fileManager
            )
            guard bookmarksURL != nil || sessionURL != nil else { return nil }
            return BrowserDetectedImportProfile(
                id: directoryName,
                name: displayNames[directoryName]
                    ?? (directoryName == "Default"
                        ? "Personal"
                        : directoryName),
                bookmarksURL: bookmarksURL,
                sessionURL: sessionURL
            )
        }
    }

    private static func chromiumProfileDisplayNames(
        at localStateURL: URL,
        fileManager: FileManager
    ) -> [String: String] {
        guard existingFile(localStateURL, fileManager: fileManager) != nil,
            let data = try? Data(contentsOf: localStateURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: Any]
        else { return [:] }
        return cache.reduce(into: [:]) { result, entry in
            guard let details = entry.value as? [String: Any],
                let name = details["name"] as? String,
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return
            }
            result[entry.key] = name
        }
    }

    private static func chromiumProfileOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Default" { return rhs != "Default" }
        if rhs == "Default" { return false }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func profileDirectories(
        below root: URL,
        fileManager: FileManager
    ) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        } ?? []
    }

    private static func newestMatchingFile(
        below root: URL,
        names: Set<String>,
        prefixes: [String] = [],
        fileManager: FileManager
    ) -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return nil }

        var matches: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard names.contains(name) || prefixes.contains(where: name.hasPrefix) else {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            matches.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return matches.max { $0.modifiedAt < $1.modifiedAt }?.url
    }
}
