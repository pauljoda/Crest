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
        let searchDirectories: [URL]
        switch extensionIdentity {
        case .chromeWebStore:
            searchDirectories = chromeSearchDirectories
        case .mozillaAddons:
            searchDirectories = mozillaSearchDirectories
        }
        let manifestURL = searchDirectories.lazy
            .map { $0.appending(path: "\(hostName).json") }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
        guard let manifestURL else {
            throw BrowserNativeMessagingHostError.hostNotFound(hostName)
        }
        let data = try Data(contentsOf: manifestURL)
        guard
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            object["name"] as? String == hostName,
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
