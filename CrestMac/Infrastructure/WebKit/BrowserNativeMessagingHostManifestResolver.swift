import Foundation
import WebKit

struct BrowserNativeMessagingHostManifestResolver {
    let chromeSearchDirectories: [URL]
    let mozillaSearchDirectories: [URL]
    let builtInHosts: [BrowserNativeMessagingBuiltInHost]

    init(
        searchDirectories: [URL],
        builtInHosts: [BrowserNativeMessagingBuiltInHost] = []
    ) {
        chromeSearchDirectories = searchDirectories
        mozillaSearchDirectories = searchDirectories
        self.builtInHosts = builtInHosts
    }

    init(
        chromeSearchDirectories: [URL],
        mozillaSearchDirectories: [URL],
        builtInHosts: [BrowserNativeMessagingBuiltInHost] = []
    ) {
        self.chromeSearchDirectories = chromeSearchDirectories
        self.mozillaSearchDirectories = mozillaSearchDirectories
        self.builtInHosts = builtInHosts
    }

    static func production() -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self(
            chromeSearchDirectories: [
                home.appending(
                    path: "Library/Application Support/Google/Chrome/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
                home.appending(
                    path: "Library/Application Support/Chromium/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
                URL(
                    filePath: "/Library/Google/Chrome/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
                URL(
                    filePath: "/Library/Application Support/Chromium/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
            ],
            mozillaSearchDirectories: [
                home.appending(
                    path: "Library/Application Support/Mozilla/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
                URL(
                    filePath: "/Library/Application Support/Mozilla/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
            ],
            builtInHosts: Self.applePasswordManagerHosts()
        )
    }

    func resolve(
        hostName: String,
        extensionID: BrowserChromeExtensionID
    ) throws -> BrowserNativeMessagingHostManifest {
        try resolve(
            hostName: hostName,
            extensionIdentity: .chromeWebStore(extensionID)
        )
    }

    func resolve(
        hostName: String,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity
    ) throws -> BrowserNativeMessagingHostManifest {
        if hostName.isEmpty {
            return try resolveUnnamedHost(for: extensionIdentity)
        }
        guard Self.isValidHostName(hostName) else {
            throw BrowserNativeMessagingHostError.invalidHostName
        }
        if case .chromeWebStore(let extensionID) = extensionIdentity,
            let host = builtInHosts.first(where: {
                $0.name == hostName && $0.extensionID == extensionID
            })
        {
            let executableURL = host.executableURL.standardizedFileURL
            guard
                FileManager.default.isExecutableFile(
                    atPath: executableURL.path
                )
            else {
                throw BrowserNativeMessagingHostError.invalidManifest
            }
            return BrowserNativeMessagingHostManifest(
                name: hostName,
                executableURL: executableURL,
                arguments: [
                    "chrome-extension://\(extensionID.rawValue)/"
                ]
            )
        }
        let directories = searchDirectories(for: extensionIdentity)
        let manifestURL = directories.lazy
            .map { $0.appending(path: "\(hostName).json") }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
        guard let manifestURL else {
            throw BrowserNativeMessagingHostError.hostNotFound(hostName)
        }
        return try resolveManifest(
            at: manifestURL,
            expectedHostName: hostName,
            extensionIdentity: extensionIdentity
        )
    }

    private func resolveUnnamedHost(
        for extensionIdentity: BrowserExtensionNativeMessagingIdentity
    ) throws -> BrowserNativeMessagingHostManifest {
        var matchesByName: [String: BrowserNativeMessagingHostManifest] = [:]
        if case .chromeWebStore(let extensionID) = extensionIdentity {
            for host in builtInHosts where host.extensionID == extensionID {
                let executableURL = host.executableURL.standardizedFileURL
                guard
                    FileManager.default.isExecutableFile(
                        atPath: executableURL.path
                    )
                else { continue }
                matchesByName[host.name] = BrowserNativeMessagingHostManifest(
                    name: host.name,
                    executableURL: executableURL,
                    arguments: [
                        "chrome-extension://\(extensionID.rawValue)/"
                    ]
                )
            }
        }
        for registeredManifest in registeredManifests(
            for: extensionIdentity
        ) {
            guard
                let host = try? resolveManifest(
                    at: registeredManifest.url,
                    expectedHostName: registeredManifest.name,
                    extensionIdentity: extensionIdentity
                ), matchesByName[host.name] == nil
            else { continue }
            matchesByName[host.name] = host
        }
        guard matchesByName.count == 1, let match = matchesByName.values.first
        else {
            throw BrowserNativeMessagingHostError.unnamedHostUnavailable
        }
        return match
    }

    private func resolveManifest(
        at manifestURL: URL,
        expectedHostName: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity
    ) throws -> BrowserNativeMessagingHostManifest {
        let data = try Data(contentsOf: manifestURL)
        guard
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let hostName = object["name"] as? String,
            Self.isValidHostName(hostName),
            expectedHostName == nil || expectedHostName == hostName,
            object["type"] as? String == "stdio",
            let path = object["path"] as? String,
            path.hasPrefix("/")
        else {
            throw BrowserNativeMessagingHostError.invalidManifest
        }
        let arguments: [String]
        switch extensionIdentity {
        case .chromeWebStore(let extensionID):
            guard let origins = object["allowed_origins"] as? [String] else {
                throw BrowserNativeMessagingHostError.invalidManifest
            }
            let expectedOrigin =
                "chrome-extension://\(extensionID.rawValue)/"
            guard origins.contains(expectedOrigin) else {
                throw BrowserNativeMessagingHostError.originNotAllowed
            }
            arguments = [expectedOrigin]
        case .mozillaAddons(let extensionID):
            guard
                let extensionIDs = object["allowed_extensions"] as? [String]
            else {
                throw BrowserNativeMessagingHostError.invalidManifest
            }
            guard extensionIDs.contains(extensionID.rawValue) else {
                throw BrowserNativeMessagingHostError.originNotAllowed
            }
            arguments = [manifestURL.path, extensionID.rawValue]
        }
        let executableURL = URL(filePath: path).standardizedFileURL
        guard
            FileManager.default.isExecutableFile(
                atPath: executableURL.path
            )
        else {
            throw BrowserNativeMessagingHostError.invalidManifest
        }
        return BrowserNativeMessagingHostManifest(
            name: hostName,
            executableURL: executableURL,
            arguments: arguments
        )
    }

    private func searchDirectories(
        for extensionIdentity: BrowserExtensionNativeMessagingIdentity
    ) -> [URL] {
        switch extensionIdentity {
        case .chromeWebStore:
            chromeSearchDirectories
        case .mozillaAddons:
            mozillaSearchDirectories
        }
    }

    private func registeredManifests(
        for extensionIdentity: BrowserExtensionNativeMessagingIdentity
    ) -> [(name: String, url: URL)] {
        var seenNames: Set<String> = []
        var manifests: [(name: String, url: URL)] = []
        for directory in searchDirectories(for: extensionIdentity) {
            let contents =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
            let registeredURLs = contents
                .filter {
                    $0.pathExtension == "json"
                        && FileManager.default.isReadableFile(atPath: $0.path)
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in registeredURLs {
                let name = url.deletingPathExtension().lastPathComponent
                guard
                    Self.isValidHostName(name),
                    seenNames.insert(name).inserted
                else { continue }
                manifests.append((name: name, url: url))
            }
        }
        return manifests
    }

    private static func isValidHostName(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.first != ".",
            value.last != ".",
            !value.contains("..")
        else { return false }
        return value.utf8.allSatisfy {
            (0x61...0x7a).contains($0)
                || (0x30...0x39).contains($0)
                || $0 == 0x5f || $0 == 0x2e
        }
    }

    private static func applePasswordManagerHosts()
        -> [BrowserNativeMessagingBuiltInHost]
    {
        // Apple's helper admits browsers carrying this managed entitlement.
        // Keep the route dormant until the current signature has it so an
        // unapproved build fails closed instead of attempting a denied launch.
        guard BrowserICloudPasswordsCapability.currentBuild == .available else {
            return []
        }
        guard
            let extensionID = BrowserChromeExtensionID(
                "pejdijmoenmkgeppbflobdenhhabjlaj"
            )
        else { return [] }
        let executableURL = URL(
            filePath:
                "/System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app/Contents/MacOS/PasswordManagerBrowserExtensionHelper"
        )
        guard
            FileManager.default.isExecutableFile(
                atPath: executableURL.path
            )
        else { return [] }
        return [
            BrowserNativeMessagingBuiltInHost(
                name: "com.apple.passwordmanager",
                extensionID: extensionID,
                executableURL: executableURL
            )
        ]
    }
}
