import Foundation

struct BrowserChromeWebStoreCompatibilityPackagePreparer {
    static let onePasswordExtensionID =
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    static let iCloudPasswordsExtensionID =
        "pejdijmoenmkgeppbflobdenhhabjlaj"

    private let fileManager: FileManager
    private let expandArchive: (URL, URL) throws -> Void

    init(
        fileManager: FileManager = .default,
        expandArchive: @escaping (URL, URL) throws -> Void = Self.expand
    ) {
        self.fileManager = fileManager
        self.expandArchive = expandArchive
    }

    func prepare(
        _ package: BrowserVerifiedCRX3Package,
        requestedPermissions: [String]
    ) throws -> BrowserChromeWebStorePreparedPackage? {
        guard
            Self.requiresCompatibilityLayer(
                extensionID: package.extensionID.rawValue,
                requestedPermissions: requestedPermissions
            )
        else {
            return nil
        }

        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-verified-extension-compatibility-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let archiveURL = rootURL.appending(path: "verified-package.zip")
        let resourceURL = rootURL.appending(
            path: "resources",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            try package.zipArchiveData.write(
                to: archiveURL,
                options: [.atomic]
            )
            try expandArchive(archiveURL, resourceURL)
            try installCompatibilityLayer(
                in: resourceURL,
                extensionID: package.extensionID.rawValue
            )
            return BrowserChromeWebStorePreparedPackage(
                resourceURL: resourceURL,
                rootURL: rootURL,
                fileManager: fileManager
            )
        } catch {
            try? fileManager.removeItem(at: rootURL)
            throw error
        }
    }

    func prepareStoredArchive(
        _ archiveURL: URL,
        extensionID: String,
        requestedPermissions: [String]
    ) throws -> BrowserChromeWebStorePreparedPackage? {
        guard
            Self.requiresCompatibilityLayer(
                extensionID: extensionID,
                requestedPermissions: requestedPermissions
            )
        else {
            return nil
        }

        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-restored-extension-compatibility-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let resourceURL = rootURL.appending(
            path: "resources",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            try expandArchive(archiveURL, resourceURL)
            try installCompatibilityLayer(
                in: resourceURL,
                extensionID: extensionID
            )
            return BrowserChromeWebStorePreparedPackage(
                resourceURL: resourceURL,
                rootURL: rootURL,
                fileManager: fileManager
            )
        } catch {
            try? fileManager.removeItem(at: rootURL)
            throw error
        }
    }

    @discardableResult
    func installCompatibilityLayer(
        in resourceURL: URL,
        extensionID: String
    ) throws -> Bool {
        switch extensionID {
        case Self.onePasswordExtensionID:
            return try installNotificationCompatibilityLayer(
                in: resourceURL,
                extensionID: extensionID
            )
        case Self.iCloudPasswordsExtensionID:
            return try installICloudPasswordsCompatibilityLayer(
                in: resourceURL
            )
        default:
            return false
        }
    }

    @discardableResult
    func installNotificationCompatibilityLayer(
        in resourceURL: URL,
        extensionID: String
    ) throws -> Bool {
        guard extensionID == Self.onePasswordExtensionID else {
            return false
        }
        let manifestURL = resourceURL.appending(path: "manifest.json")
        let data = try Data(contentsOf: manifestURL)
        guard
            let manifest = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            manifest["manifest_version"] as? Int == 3,
            let background = manifest["background"]
                as? [String: Any],
            background["type"] as? String == "module",
            let serviceWorker = background["service_worker"] as? String
        else {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .invalidBackgroundManifest
        }
        guard Self.isSafeRelativePath(serviceWorker) else {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .unsafeBackgroundPath
        }
        let originalWorkerURL = resourceURL.appending(path: serviceWorker)
            .standardizedFileURL
        guard
            originalWorkerURL.path.hasPrefix(
                resourceURL.standardizedFileURL.path + "/"
            ), fileManager.fileExists(atPath: originalWorkerURL.path)
        else {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .unsafeBackgroundPath
        }

        let originalWorker = try String(
            contentsOf: originalWorkerURL,
            encoding: .utf8
        )
        let preparedWorker =
            Self.notificationCompatibilityScript()
            + "\n\n"
            + originalWorker
        try preparedWorker.write(
            to: originalWorkerURL,
            atomically: true,
            encoding: .utf8
        )
        return true
    }

    @discardableResult
    private func installICloudPasswordsCompatibilityLayer(
        in resourceURL: URL
    ) throws -> Bool {
        let manifestURL = resourceURL.appending(path: "manifest.json")
        let data = try Data(contentsOf: manifestURL)
        guard
            let manifest = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            manifest["manifest_version"] as? Int == 3,
            let background = manifest["background"]
                as? [String: Any],
            let serviceWorker = background["service_worker"] as? String
        else {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .invalidBackgroundManifest
        }
        guard Self.isSafeRelativePath(serviceWorker) else {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .unsafeBackgroundPath
        }
        let originalWorkerURL = resourceURL.appending(path: serviceWorker)
            .standardizedFileURL
        guard
            originalWorkerURL.path.hasPrefix(
                resourceURL.standardizedFileURL.path + "/"
            ), fileManager.fileExists(atPath: originalWorkerURL.path)
        else {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .unsafeBackgroundPath
        }
        let originalWorker = try String(
            contentsOf: originalWorkerURL,
            encoding: .utf8
        )
        try
            (Self.iCloudPasswordsCompatibilityScript()
            + "\n\n"
            + originalWorker).write(
                to: originalWorkerURL,
                atomically: true,
                encoding: .utf8
            )
        return true
    }

    static func requiresCompatibilityLayer(
        extensionID: String,
        requestedPermissions: [String]
    ) -> Bool {
        requiresNotificationCompatibilityLayer(
            extensionID: extensionID,
            requestedPermissions: requestedPermissions
        )
            || (extensionID == iCloudPasswordsExtensionID
                && requestedPermissions.contains("nativeMessaging")
                && requestedPermissions.contains("webNavigation"))
    }

    static func requiresNotificationCompatibilityLayer(
        extensionID: String,
        requestedPermissions: [String]
    ) -> Bool {
        extensionID == onePasswordExtensionID
            && requestedPermissions.contains("nativeMessaging")
            && requestedPermissions.contains("notifications")
    }

    private static func expand(_ archiveURL: URL, to resourceURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-x",
            "-k",
            archiveURL.path,
            resourceURL.path,
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .archiveExpansionFailed
        }
        guard process.terminationStatus == 0 else {
            throw BrowserChromeWebStoreCompatibilityPackageError
                .archiveExpansionFailed
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
            !path.hasPrefix("/"),
            !path.contains("\\")
        else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func notificationCompatibilityScript() -> String {
        """
        // Crest's WKWebExtension host currently has no notifications API.
        // 1Password uses notifications only for auxiliary desktop banners, but
        // registers their event listeners while its background worker starts.
        // Supply a deliberately no-op surface so its core native connection,
        // unlock, and fill features can continue to initialize.
        const crestNoopEvent = Object.freeze({
            addListener() {},
            removeListener() {},
            hasListener() { return false; },
            hasListeners() { return false; }
        });

        const crestCallback = (args, value) => {
            const callback = args.at(-1);
            if (typeof callback === "function") {
                queueMicrotask(() => callback(value));
            }
        };

        const crestNotifications = Object.freeze({
            onClicked: crestNoopEvent,
            onButtonClicked: crestNoopEvent,
            onClosed: crestNoopEvent,
            onPermissionLevelChanged: crestNoopEvent,
            create(...args) {
                const id = typeof args[0] === "string"
                    ? args[0]
                    : `crest-${Date.now()}`;
                crestCallback(args, id);
                return Promise.resolve(id);
            },
            clear(...args) {
                crestCallback(args, true);
                return Promise.resolve(true);
            },
            getAll(...args) {
                crestCallback(args, {});
                return Promise.resolve({});
            },
            getPermissionLevel(...args) {
                crestCallback(args, "denied");
                return Promise.resolve("denied");
            },
            update(...args) {
                crestCallback(args, false);
                return Promise.resolve(false);
            }
        });

        const crestNativeChrome = globalThis.chrome;
        if (crestNativeChrome && !crestNativeChrome.notifications) {
            Object.defineProperty(crestNativeChrome, "notifications", {
                value: crestNotifications,
                configurable: true
            });
        }

        const crestWebNavigation = crestNativeChrome?.webNavigation;
        if (crestWebNavigation
            && !crestWebNavigation.onCreatedNavigationTarget) {
            const crestWebNavigationCompatibility = new Proxy(
                crestWebNavigation,
                {
                    get(target, property) {
                        if (property === "onCreatedNavigationTarget") {
                            return crestNoopEvent;
                        }
                        return Reflect.get(target, property, target);
                    }
                }
            );
            const crestChromeCompatibility = new Proxy(
                crestNativeChrome,
                {
                    get(target, property) {
                        if (property === "webNavigation") {
                            return crestWebNavigationCompatibility;
                        }
                        return Reflect.get(target, property, target);
                    }
                }
            );
            Object.defineProperty(globalThis, "chrome", {
                value: crestChromeCompatibility,
                configurable: true
            });
        }
        """
    }

    private static func iCloudPasswordsCompatibilityScript() -> String {
        """
        // WebKit does not currently expose Chrome's SPA history-navigation
        // event. Keep iCloud Passwords running for ordinary page loads while
        // making the missing SPA refresh behavior explicit and inert.
        const crestICloudNoopEvent = Object.freeze({
            addListener() {},
            removeListener() {},
            hasListener() { return false; },
            hasListeners() { return false; }
        });

        const crestICloudChrome = globalThis.chrome;
        const crestICloudNavigation = crestICloudChrome?.webNavigation;
        if (crestICloudChrome && crestICloudNavigation) {
            const crestICloudMissingNavigationEvents = new Set([
                "onHistoryStateUpdated",
                "onTabReplaced"
            ].filter((name) => !crestICloudNavigation[name]));
            const crestICloudNavigationCompatibility = new Proxy(
                crestICloudNavigation,
                {
                    get(target, property) {
                        if (crestICloudMissingNavigationEvents.has(property)) {
                            return crestICloudNoopEvent;
                        }
                        return Reflect.get(target, property, target);
                    }
                }
            );
            const crestICloudUncontrollableSetting = Object.freeze({
                onChange: crestICloudNoopEvent,
                get() {
                    return Promise.resolve({
                        value: false,
                        levelOfControl: "not_controllable"
                    });
                },
                set() { return Promise.resolve(); },
                clear() { return Promise.resolve(); }
            });
            const crestICloudNativePrivacy = crestICloudChrome.privacy;
            const crestICloudNativeServices =
                crestICloudNativePrivacy?.services;
            const crestICloudServicesCompatibility = new Proxy(
                crestICloudNativeServices ?? {},
                {
                    get(target, property) {
                        if ([
                            "passwordSavingEnabled",
                            "autofillCreditCardEnabled",
                            "autofillAddressEnabled"
                        ].includes(property)) {
                            return Reflect.get(target, property, target)
                                ?? crestICloudUncontrollableSetting;
                        }
                        return Reflect.get(target, property, target);
                    }
                }
            );
            const crestICloudPrivacyCompatibility = new Proxy(
                crestICloudNativePrivacy ?? {},
                {
                    get(target, property) {
                        if (property === "services") {
                            return crestICloudServicesCompatibility;
                        }
                        return Reflect.get(target, property, target);
                    }
                }
            );
            const crestICloudChromeCompatibility = new Proxy(
                crestICloudChrome,
                {
                    get(target, property) {
                        if (property === "webNavigation") {
                            return crestICloudNavigationCompatibility;
                        }
                        if (property === "privacy") {
                            return crestICloudPrivacyCompatibility;
                        }
                        return Reflect.get(target, property, target);
                    }
                }
            );
            Object.defineProperty(globalThis, "chrome", {
                value: crestICloudChromeCompatibility,
                configurable: true
            });
        }
        """
    }
}
