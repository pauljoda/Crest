import CryptoKit
import Foundation
import WebKit

enum BrowserWebExtensionManifestCompatibilityPolicy {
    @MainActor
    static func displayErrors(
        for webExtension: WKWebExtension
    ) -> [String] {
        webExtension.errors.compactMap { reportedError in
            let error = reportedError as NSError
            guard
                !isValidEmptyActionCommandWarning(
                    error,
                    manifest: webExtension.manifest
                )
            else {
                return nil
            }
            return error.localizedDescription
        }.sorted()
    }

    static func normalizeCommandsForWebKit(
        in manifest: inout [String: Any]
    ) {
        guard var commands = manifest["commands"] as? [String: Any]
        else { return }

        // WebKit uses the cross-version action command name. Preserve the
        // extension-facing manifest in the generated runtime, while presenting
        // the equivalent modern spelling to WKWebExtension.
        for legacyName in [
            "_execute_browser_action",
            "_execute_page_action",
        ] {
            guard let legacyCommand = commands.removeValue(forKey: legacyName)
            else { continue }
            if commands["_execute_action"] == nil {
                commands["_execute_action"] = legacyCommand
            }
        }

        // `_execute_action` is a reserved command whose description and
        // shortcut are both optional. WebKit reports the legal empty form as
        // invalid and ignores it at runtime, so omit only that inert reserved
        // entry from WebKit's copy. `runtime.getManifest()` continues to return
        // the untouched extension-authored manifest.
        if let actionCommand = commands["_execute_action"] as? [String: Any],
            actionCommand.isEmpty
        {
            commands.removeValue(forKey: "_execute_action")
        }
        manifest["commands"] = commands
    }

    private static func isValidEmptyActionCommandWarning(
        _ error: NSError,
        manifest: [String: Any]
    ) -> Bool {
        guard
            error.domain == WKWebExtension.errorDomain,
            error.code == WKWebExtension.Error.invalidManifestEntry.rawValue,
            let commands = manifest["commands"] as? [String: Any],
            let actionCommand = commands["_execute_action"]
                as? [String: Any],
            actionCommand.isEmpty
        else {
            return false
        }
        let description = error.localizedDescription.lowercased()
        return description.contains("empty or invalid command")
            && description.contains("commands")
    }
}

struct BrowserWebExtensionCompatibilityPackagePreparer {
    static let internalContextMenuTransportPermission = "nativeMessaging"
    private static let legacyBackgroundPreludePattern =
        #"(?s)\A// Crest's WKWebExtension host currently has no notifications API\.\s*.*?Object\.defineProperty\(globalThis, \"chrome\", \{\s*value: crestChromeCompatibility,\s*configurable: true\s*\}\);\s*\}\s*"#
    private static let emulatedPermissions: Set<String> = [
        "contextMenus",
        "downloads",
        "history",
        "identity",
        "idle",
        "management",
        "menus",
        "notifications",
        "offscreen",
        "omnibox",
        "privacy",
        "topSites",
        "webNavigation",
        "webRequest",
    ]

    private let fileManager: FileManager
    private let expandArchive: (URL, URL) throws -> Void

    init(
        fileManager: FileManager = .default,
        expandArchive: @escaping (URL, URL) throws -> Void = Self.expand
    ) {
        self.fileManager = fileManager
        self.expandArchive = expandArchive
    }

    func prepareStoredResource(
        _ storedResourceURL: URL,
        requestedPermissions: [String],
        runtimeIdentity: BrowserExtensionRuntimeIdentity
    ) throws -> BrowserWebExtensionPreparedPackage? {
        guard
            Self.requiresCompatibilityLayer(
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
            let resourceValues = try storedResourceURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            if resourceValues.isDirectory == true {
                try fileManager.copyItem(
                    at: storedResourceURL,
                    to: resourceURL
                )
            } else if resourceValues.isRegularFile == true {
                try expandArchive(storedResourceURL, resourceURL)
            } else {
                throw BrowserWebExtensionCompatibilityPackageError
                    .archiveExpansionFailed
            }
            let installed = try installCompatibilityLayer(
                in: resourceURL,
                requestedPermissions: requestedPermissions,
                runtimeIdentity: runtimeIdentity
            )
            guard installed else {
                try? fileManager.removeItem(at: rootURL)
                return nil
            }
            return BrowserWebExtensionPreparedPackage(
                resourceURL: resourceURL,
                rootURL: rootURL,
                fileManager: fileManager,
                internalGrantedPermissions: Self.internalGrantedPermissions(
                    requestedPermissions: requestedPermissions
                )
            )
        } catch {
            try? fileManager.removeItem(at: rootURL)
            throw error
        }
    }

    @discardableResult
    func installCompatibilityLayer(
        in resourceURL: URL,
        requestedPermissions: [String],
        runtimeIdentity: BrowserExtensionRuntimeIdentity
    ) throws -> Bool {
        guard
            Self.requiresCompatibilityLayer(
                requestedPermissions: requestedPermissions
            )
        else {
            return false
        }
        let manifestURL = resourceURL.appending(path: "manifest.json")
        let data = try Data(contentsOf: manifestURL)
        guard
            var manifest = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let manifestVersion = manifest["manifest_version"] as? Int,
            manifestVersion == 2 || manifestVersion == 3
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let compatibilityScript = try Self.webExtensionCompatibilityScript(
            manifest: manifest,
            runtimeIdentity: runtimeIdentity
        )
        Self.normalizeManifestForWebKit(
            &manifest,
            requestedPermissions: requestedPermissions
        )
        let compatibilityScriptName = Self.generatedJavaScriptName(
            prefix: "crest-webextension-compatibility",
            source: compatibilityScript
        )
        try compatibilityScript.write(
            to: resourceURL.appending(path: compatibilityScriptName),
            atomically: true,
            encoding: .utf8
        )
        var installed = try installBackgroundCompatibility(
            in: resourceURL,
            manifest: &manifest,
            compatibilityScriptName: compatibilityScriptName
        )
        installed =
            try installExtensionPageCompatibility(
                in: resourceURL,
                manifest: manifest,
                compatibilityScriptName: compatibilityScriptName
            ) || installed
        installed =
            Self.installContentScriptCompatibility(
                in: &manifest,
                compatibilityScriptName: compatibilityScriptName
            )
            || installed

        guard installed else {
            try? fileManager.removeItem(
                at: resourceURL.appending(path: compatibilityScriptName)
            )
            return false
        }
        let updatedManifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try updatedManifestData.write(to: manifestURL, options: [.atomic])
        return true
    }

    private func installBackgroundCompatibility(
        in resourceURL: URL,
        manifest: inout [String: Any],
        compatibilityScriptName: String
    ) throws -> Bool {
        guard var background = manifest["background"] as? [String: Any] else {
            return false
        }

        if let serviceWorker = background["service_worker"] as? String {
            let workerURL = try validatedResourceURL(
                for: serviceWorker,
                in: resourceURL
            )
            let storedWorker = try String(
                contentsOf: workerURL,
                encoding: .utf8
            )
            let originalWorker = Self.removingLegacyBackgroundPrelude(
                from: storedWorker
            )
            if originalWorker != storedWorker {
                try originalWorker.write(
                    to: workerURL,
                    atomically: true,
                    encoding: .utf8
                )
            }

            // WebKit backs a worker background with one service-worker
            // registration per origin, and re-registering an unchanged
            // script resolves against the existing registration without
            // evaluating the worker again. The second context that loads
            // the same extension origin — one extension enabled in two
            // Spaces of a profile — is then told its background loaded
            // while its `runtime` listeners never come to exist, and its
            // popup's opening message is answered with nothing. Background
            // documents are WebKit's other first-class environment for the
            // same code and are created per context, so worker code moves
            // into one wherever its module form allows.
            if background["type"] as? String == "module" {
                let backgroundDocumentName = try installBackgroundDocument(
                    in: resourceURL,
                    serviceWorker: serviceWorker,
                    compatibilityScriptName: compatibilityScriptName
                )
                manifest["background"] = ["page": backgroundDocumentName]
                return true
            }

            if var scripts = background["scripts"] as? [String],
                !scripts.isEmpty
            {
                // A dual-environment manifest already ships document-ready
                // background scripts alongside its worker.
                if !scripts.contains(compatibilityScriptName) {
                    scripts.insert(compatibilityScriptName, at: 0)
                }
                background["scripts"] = scripts
                background.removeValue(forKey: "service_worker")
                background.removeValue(forKey: "preferred_environment")
                manifest["background"] = background
                return true
            }

            // A classic worker may call `importScripts`, which no document
            // can offer under the extension's content security policy, so
            // it keeps the worker environment behind the bootstrap.
            let backgroundBootstrapName = try installServiceWorkerBootstrap(
                in: resourceURL,
                serviceWorker: serviceWorker,
                compatibilityScriptName: compatibilityScriptName
            )
            background["service_worker"] = backgroundBootstrapName
            background.removeValue(forKey: "scripts")
            background.removeValue(forKey: "preferred_environment")
            background.removeValue(forKey: "persistent")
            manifest["background"] = background
            return true
        }

        if var scripts = background["scripts"] as? [String] {
            if !scripts.contains(compatibilityScriptName) {
                scripts.insert(compatibilityScriptName, at: 0)
            }
            background["scripts"] = scripts
            manifest["background"] = background
            return true
        }

        if let page = background["page"] as? String {
            return try injectCompatibilityScript(
                into: page,
                in: resourceURL,
                compatibilityScriptName: compatibilityScriptName
            )
        }
        return false
    }

    private static func removingLegacyBackgroundPrelude(
        from source: String
    ) -> String {
        guard
            let range = source.range(
                of: legacyBackgroundPreludePattern,
                options: .regularExpression
            )
        else {
            return source
        }
        return String(source[range.upperBound...])
    }

    private func installServiceWorkerBootstrap(
        in resourceURL: URL,
        serviceWorker: String,
        compatibilityScriptName: String
    ) throws -> String {
        let compatibilitySpecifier = Self.javascriptStringLiteral(
            "./\(compatibilityScriptName)"
        )
        let workerSpecifier = Self.javascriptStringLiteral("./\(serviceWorker)")
        let backgroundBootstrap =
            "importScripts(\(compatibilitySpecifier), \(workerSpecifier));"
        let backgroundBootstrapName = Self.generatedJavaScriptName(
            prefix: "crest-webextension-background-bootstrap",
            source: backgroundBootstrap
        )
        try backgroundBootstrap.write(
            to: resourceURL.appending(path: backgroundBootstrapName),
            atomically: true,
            encoding: .utf8
        )
        return backgroundBootstrapName
    }

    /// The compatibility script tag matches `injectCompatibilityScript`'s
    /// exactly so the page enumerator recognizes it as already installed.
    private func installBackgroundDocument(
        in resourceURL: URL,
        serviceWorker: String,
        compatibilityScriptName: String
    ) throws -> String {
        let backgroundDocument =
            """
            <!DOCTYPE html>
            <meta charset="utf-8">
            <script src="/\(compatibilityScriptName)"></script>
            <script type="module" src="/\(Self.htmlAttributeEscaped(serviceWorker))"></script>
            """
        let backgroundDocumentName = Self.generatedFileName(
            prefix: "crest-webextension-background",
            pathExtension: "html",
            source: backgroundDocument
        )
        try backgroundDocument.write(
            to: resourceURL.appending(path: backgroundDocumentName),
            atomically: true,
            encoding: .utf8
        )
        return backgroundDocumentName
    }

    private static func htmlAttributeEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }

    static func requiresCompatibilityLayer(
        requestedPermissions: [String]
    ) -> Bool {
        !emulatedPermissions.isDisjoint(with: requestedPermissions)
    }

    private static func normalizeManifestForWebKit(
        _ manifest: inout [String: Any],
        requestedPermissions: [String]
    ) {
        BrowserWebExtensionManifestCompatibilityPolicy
            .normalizeCommandsForWebKit(in: &manifest)
        guard
            requestedPermissions.contains("contextMenus")
                || requestedPermissions.contains("menus")
        else { return }
        var permissions = manifest["permissions"] as? [String] ?? []
        if !permissions.contains(internalContextMenuTransportPermission) {
            permissions.append(internalContextMenuTransportPermission)
        }
        manifest["permissions"] = permissions
    }

    static func internalGrantedPermissions(
        requestedPermissions: [String]
    ) -> Set<String> {
        (requestedPermissions.contains("contextMenus")
            || requestedPermissions.contains("menus"))
            && !requestedPermissions.contains(
                internalContextMenuTransportPermission
            )
            ? [internalContextMenuTransportPermission]
            : []
    }

    private func installExtensionPageCompatibility(
        in resourceURL: URL,
        manifest: [String: Any],
        compatibilityScriptName: String
    ) throws -> Bool {
        var installed = false
        let sandboxPages = Self.sandboxPagePaths(in: manifest)
        guard
            let enumerator = fileManager.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
        else { return false }

        let resourcePath = resourceURL.standardizedFileURL.path
        for case let pageURL as URL in enumerator {
            let values = try pageURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                ["html", "htm"].contains(
                    pageURL.pathExtension.lowercased()
                )
            else { continue }

            let pagePath = pageURL.standardizedFileURL.path
            guard pagePath.hasPrefix(resourcePath + "/") else { continue }
            let relativePath = String(
                pagePath.dropFirst(resourcePath.count + 1)
            )
            guard !sandboxPages.contains(relativePath) else { continue }
            installed =
                try injectCompatibilityScript(
                    into: relativePath,
                    in: resourceURL,
                    compatibilityScriptName: compatibilityScriptName
                ) || installed
        }
        return installed
    }

    private static func sandboxPagePaths(
        in manifest: [String: Any]
    ) -> Set<String> {
        guard
            let sandbox = manifest["sandbox"] as? [String: Any],
            let pages = sandbox["pages"] as? [String]
        else { return [] }
        return Set(pages.filter(isSafeRelativePath))
    }

    private static func installContentScriptCompatibility(
        in manifest: inout [String: Any],
        compatibilityScriptName: String
    ) -> Bool {
        guard
            var declarations = manifest["content_scripts"]
                as? [[String: Any]]
        else { return false }

        var installed = false
        for index in declarations.indices {
            guard var scripts = declarations[index]["js"] as? [String]
            else { continue }
            if !scripts.contains(compatibilityScriptName) {
                scripts.insert(compatibilityScriptName, at: 0)
                declarations[index]["js"] = scripts
                installed = true
            }
        }
        if installed {
            manifest["content_scripts"] = declarations
        }
        return installed
    }

    private func injectCompatibilityScript(
        into relativePath: String,
        in resourceURL: URL,
        compatibilityScriptName: String
    ) throws -> Bool {
        let pageURL = try validatedResourceURL(
            for: relativePath,
            in: resourceURL
        )
        let storedSource = try String(contentsOf: pageURL, encoding: .utf8)
        let emptyLocalizationAttributePattern =
            #"(?i)(?<=\s)(?:aria-label|placeholder|data-i18n(?:-title|-tip)?)(?:\s*=\s*(?:"\s*"|'\s*'))?(?=\s|/?>)"#
        var source = storedSource.replacingOccurrences(
            of: emptyLocalizationAttributePattern,
            with: "",
            options: .regularExpression
        )
        let compatibilityTag =
            #"<script src="/\#(compatibilityScriptName)"></script>"#
        var tags: [String] = []
        if !source.contains(compatibilityTag) {
            tags.append(compatibilityTag)
        }
        guard source != storedSource || !tags.isEmpty else { return false }

        if !tags.isEmpty {
            let injection = tags.joined(separator: "\n")
            if let headStart = source.range(
                of: "<head",
                options: [.caseInsensitive]
            ),
                let headEnd = source.range(
                    of: ">",
                    range: headStart.lowerBound..<source.endIndex
                )
            {
                source.insert(
                    contentsOf: "\n\(injection)",
                    at: headEnd.upperBound
                )
            } else {
                source.insert(
                    contentsOf: injection + "\n",
                    at: source.startIndex
                )
            }
        }
        try source.write(to: pageURL, atomically: true, encoding: .utf8)
        return true
    }

    private func validatedResourceURL(
        for relativePath: String,
        in resourceURL: URL
    ) throws -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            throw BrowserWebExtensionCompatibilityPackageError
                .unsafeBackgroundPath
        }
        let candidate = resourceURL.appending(path: relativePath)
            .standardizedFileURL
        guard
            candidate.path.hasPrefix(
                resourceURL.standardizedFileURL.path + "/"
            ), fileManager.fileExists(atPath: candidate.path)
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .unsafeBackgroundPath
        }
        return candidate
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
            throw BrowserWebExtensionCompatibilityPackageError
                .archiveExpansionFailed
        }
        guard process.terminationStatus == 0 else {
            throw BrowserWebExtensionCompatibilityPackageError
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

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed, .withoutEscapingSlashes]
            ),
            let literal = String(data: data, encoding: .utf8)
        else {
            preconditionFailure("A Swift String must encode as JSON.")
        }
        return literal
    }

    private static func generatedJavaScriptName(
        prefix: String,
        source: String
    ) -> String {
        generatedFileName(prefix: prefix, pathExtension: "js", source: source)
    }

    private static func generatedFileName(
        prefix: String,
        pathExtension: String,
        source: String
    ) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        let fingerprint = digest.prefix(8).map {
            String(format: "%02x", $0)
        }.joined()
        return "\(prefix)-\(fingerprint).\(pathExtension)"
    }

    private static func webExtensionCompatibilityScript(
        manifest: [String: Any],
        runtimeIdentity: BrowserExtensionRuntimeIdentity
    ) throws -> String {
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let manifestLiteral = String(
                data: manifestData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        return """
            // Crest fills browser-neutral WebExtension surface gaps only when
            // WebKit does not expose a native implementation. Keep this runtime
            // capability-based: it must never branch on an extension identity.
            (() => {
                const nativeChrome = globalThis.chrome;
                const nativeBrowser = globalThis.browser;
                const primaryRoot = nativeChrome ?? nativeBrowser;
                if (!primaryRoot) return;
                const declaredManifest = Object.freeze(\(manifestLiteral));
                const extensionID = \(javascriptStringLiteral(runtimeIdentity.extensionID));
                const extensionBaseURL = \(javascriptStringLiteral(runtimeIdentity.baseURL.absoluteString));
                const capabilityBrokerHost = \(javascriptStringLiteral(
                    ProductIdentity.serviceNamespace
                        + ".webextension-compatibility"
                ));
                const fallbackResourceURL = (path = "") => new URL(
                    String(path),
                    extensionBaseURL
                ).href;

                const installIdleCallbackFallbacks = () => {
                    if (typeof globalThis.requestIdleCallback !== "function") {
                        const requestIdleCallback = (callback) => {
                            if (typeof callback !== "function") {
                                throw new TypeError(
                                    "requestIdleCallback requires a callback"
                                );
                            }
                            return globalThis.setTimeout(() => {
                                const deadlineStartedAt = Date.now();
                                callback({
                                    didTimeout: false,
                                    timeRemaining() {
                                        return Math.max(
                                            0,
                                            50 - (Date.now()
                                                - deadlineStartedAt)
                                        );
                                    }
                                });
                            }, 1);
                        };
                        try {
                            Object.defineProperty(
                                globalThis,
                                "requestIdleCallback",
                                {
                                    value: requestIdleCallback,
                                    configurable: true,
                                    writable: true
                                }
                            );
                        } catch {
                            try {
                                globalThis.requestIdleCallback =
                                    requestIdleCallback;
                            } catch {}
                        }
                    }
                    if (typeof globalThis.cancelIdleCallback !== "function") {
                        const cancelIdleCallback = (handle) =>
                            globalThis.clearTimeout(handle);
                        try {
                            Object.defineProperty(
                                globalThis,
                                "cancelIdleCallback",
                                {
                                    value: cancelIdleCallback,
                                    configurable: true,
                                    writable: true
                                }
                            );
                        } catch {
                            try {
                                globalThis.cancelIdleCallback =
                                    cancelIdleCallback;
                            } catch {}
                        }
                    }
                };
                installIdleCallbackFallbacks();

                const installWrappedJSObjectFallback = () => {
                    const protocol = globalThis.location?.protocol;
                    if (
                        typeof protocol === "string"
                        && protocol.includes("extension")
                    ) {
                        return;
                    }
                    if (globalThis.wrappedJSObject !== undefined) return;

                    // Firefox exposes the page global through this name. WebKit
                    // cannot safely reproduce that privilege, but an empty
                    // object preserves feature probes and lets extensions take
                    // their normal script-injection fallback instead of
                    // throwing before it runs.
                    try {
                        Object.defineProperty(
                            globalThis,
                            "wrappedJSObject",
                            {
                                value: Object.create(null),
                                configurable: true
                            }
                        );
                    } catch {}
                };
                installWrappedJSObjectFallback();

                const normalizedRuntimes = new WeakSet();
                const normalizeRuntime = (nativeRuntime) => {
                    if (
                        !nativeRuntime
                        || normalizedRuntimes.has(nativeRuntime)
                    ) {
                        return;
                    }
                    normalizedRuntimes.add(nativeRuntime);

                    let nativeGetURL;
                    let descriptor;
                    try {
                        nativeGetURL = nativeRuntime.getURL;
                        descriptor = Reflect.getOwnPropertyDescriptor(
                            nativeRuntime,
                            "getURL"
                        );
                    } catch {}
                    const getURL = (path = "") => {
                        const normalizedPath = String(path);
                        if (typeof nativeGetURL === "function") {
                            try {
                                const nativeURL = Reflect.apply(
                                    nativeGetURL,
                                    nativeRuntime,
                                    [normalizedPath]
                                );
                                if (
                                    typeof nativeURL === "string"
                                    && nativeURL !== ""
                                ) {
                                    return nativeURL;
                                }
                            } catch {}
                        }
                        return fallbackResourceURL(normalizedPath);
                    };
                    try {
                        Object.defineProperty(nativeRuntime, "getURL", {
                            value: getURL,
                            configurable: true,
                            enumerable: descriptor?.enumerable ?? true
                        });
                    } catch {
                        try { nativeRuntime.getURL = getURL; } catch {}
                    }
                };

                const normalizedI18nNamespaces = new WeakMap();
                const normalizeI18n = (nativeI18n) => {
                    if (!nativeI18n) return nativeI18n;
                    if (normalizedI18nNamespaces.has(nativeI18n)) {
                        return normalizedI18nNamespaces.get(nativeI18n);
                    }

                    let nativeGetMessage;
                    let descriptor;
                    try {
                        nativeGetMessage = nativeI18n.getMessage;
                        descriptor = Reflect.getOwnPropertyDescriptor(
                            nativeI18n,
                            "getMessage"
                        );
                    } catch {}
                    if (typeof nativeGetMessage !== "function") {
                        normalizedI18nNamespaces.set(nativeI18n, nativeI18n);
                        return nativeI18n;
                    }
                    const getMessage = (name, ...substitutions) => {
                        if (name === "") return "";
                        return Reflect.apply(
                            nativeGetMessage,
                            nativeI18n,
                            [name, ...substitutions]
                        );
                    };
                    try {
                        Object.defineProperty(nativeI18n, "getMessage", {
                            value: getMessage,
                            configurable: true,
                            enumerable: descriptor?.enumerable ?? true
                        });
                    } catch {
                        try { nativeI18n.getMessage = getMessage; } catch {}
                    }
                    try {
                        if (nativeI18n.getMessage === getMessage) {
                            normalizedI18nNamespaces.set(
                                nativeI18n,
                                nativeI18n
                            );
                            return nativeI18n;
                        }
                    } catch {}

                    const facade = namespaceFacade(
                        nativeI18n,
                        {},
                        new Map([["getMessage", getMessage]])
                    );
                    normalizedI18nNamespaces.set(nativeI18n, facade);
                    normalizedI18nNamespaces.set(facade, facade);
                    return facade;
                };

                const noopEvent = Object.freeze({
                    addListener() {},
                    removeListener() {},
                    hasListener() { return false; },
                    hasListeners() { return false; }
                });
                const callbackOrPromise = (args, value) => {
                    const callback = args.at(-1);
                    if (typeof callback === "function") {
                        queueMicrotask(() => callback(value));
                    }
                    return Promise.resolve(value);
                };
                const rejectCallbackOrPromise = (args, message) => {
                    const error = new Error(message);
                    const callback = args.at(-1);
                    if (typeof callback === "function") {
                        queueMicrotask(() => callback(undefined));
                        return undefined;
                    }
                    return Promise.reject(error);
                };
                const supportedMenuPattern = (pattern) =>
                    pattern === "<all_urls>"
                    || /^(?:\\*|https?|wss?|ftp|file|data):\\/\\//
                        .test(String(pattern));
                const normalizedMenuProperties = (properties) => {
                    if (!properties || typeof properties !== "object") {
                        return properties;
                    }
                    let normalized = properties;
                    for (const property of [
                        "documentUrlPatterns",
                        "targetUrlPatterns"
                    ]) {
                        const patterns = properties[property];
                        if (!Array.isArray(patterns)) continue;
                        const supported = patterns.filter(
                            supportedMenuPattern
                        );
                        if (supported.length === patterns.length) continue;
                        if (normalized === properties) {
                            normalized = { ...properties };
                        }
                        normalized[property] = supported;
                    }
                    return normalized;
                };
                const installEventFacade = (nativeEvent, facade) => {
                    if (!nativeEvent) return false;
                    for (const [property, value] of Object.entries(facade)) {
                        let descriptor;
                        try {
                            descriptor = Reflect.getOwnPropertyDescriptor(
                                nativeEvent,
                                property
                            );
                            Object.defineProperty(nativeEvent, property, {
                                value,
                                configurable: true,
                                enumerable: descriptor?.enumerable ?? true
                            });
                        } catch {}
                        try {
                            if (nativeEvent[property] !== value) {
                                nativeEvent[property] = value;
                            }
                        } catch {}
                        try {
                            if (nativeEvent[property] !== value) {
                                return false;
                            }
                        } catch {
                            return false;
                        }
                    }
                    return true;
                };
                const normalizedMenuNamespaces = new WeakMap();
                const normalizeMenuNamespace = (nativeMenus) => {
                    if (!nativeMenus) return nativeMenus;
                    if (normalizedMenuNamespaces.has(nativeMenus)) {
                        return normalizedMenuNamespaces.get(nativeMenus);
                    }

                    const items = new Map();
                    const listeners = new Set();
                    const clickContexts = new Map();
                    const nativeClicks = new Map();
                    const installListeners = new Set();
                    const pendingInstallDetails = [];
                    const acknowledgedInstallEvents = new Set();
                    let generatedID = 0;
                    let port;
                    let reconnectHandle;
                    let installDispatchScheduled = false;

                    const scheduleInstallDispatch = () => {
                        if (
                            installDispatchScheduled
                            || pendingInstallDetails.length === 0
                            || installListeners.size === 0
                        ) {
                            return;
                        }
                        installDispatchScheduled = true;
                        queueMicrotask(() => {
                            installDispatchScheduled = false;
                            if (installListeners.size === 0) return;
                            const details = pendingInstallDetails.splice(0);
                            for (const detail of details) {
                                for (const listener of installListeners) {
                                    try { listener(detail); } catch {}
                                }
                            }
                        });
                    };
                    const onInstalled = Object.freeze({
                        addListener(listener) {
                            if (typeof listener !== "function") return;
                            installListeners.add(listener);
                            scheduleInstallDispatch();
                        },
                        removeListener(listener) {
                            installListeners.delete(listener);
                        },
                        hasListener(listener) {
                            return installListeners.has(listener);
                        },
                        hasListeners() {
                            return installListeners.size > 0;
                        }
                    });
                    const nativeRuntime = nativeBrowser?.runtime
                        ?? primaryRoot?.runtime;
                    try {
                        nativeRuntime?.onInstalled?.addListener((details) => {
                            pendingInstallDetails.push(details);
                            scheduleInstallDispatch();
                        });
                    } catch {}
                    installEventFacade(nativeRuntime?.onInstalled, onInstalled);

                    const encodedID = (value) => {
                        const kind = typeof value === "number"
                            ? "number"
                            : "string";
                        return `${kind}:${String(value)}`;
                    };
                    const decodedID = (value) => {
                        if (typeof value !== "string") return undefined;
                        const separator = value.indexOf(":");
                        if (separator < 0) return undefined;
                        const kind = value.slice(0, separator);
                        const encodedValue = value.slice(separator + 1);
                        if (kind === "string") return encodedValue;
                        if (kind !== "number") return undefined;
                        const number = Number(encodedValue);
                        return Number.isFinite(number) ? number : undefined;
                    };
                    const definition = (id, properties, existing) => {
                        const normalized = normalizedMenuProperties(
                            properties
                        ) ?? {};
                        const authored = {
                            ...(existing?.authored ?? {}),
                            ...normalized
                        };
                        const originalID = existing?.originalID ?? id;
                        return {
                            id: encodedID(originalID),
                            originalID,
                            parentId: authored.parentId === undefined
                                ? undefined
                                : encodedID(authored.parentId),
                            type: authored.type ?? "normal",
                            title: authored.title ?? "",
                            contexts: Array.isArray(authored.contexts)
                                && authored.contexts.length > 0
                                ? authored.contexts
                                : ["page"],
                            documentUrlPatterns: Array.isArray(
                                authored.documentUrlPatterns
                            )
                                ? authored.documentUrlPatterns.filter(
                                    supportedMenuPattern
                                )
                                : [],
                            targetUrlPatterns: Array.isArray(
                                authored.targetUrlPatterns
                            )
                                ? authored.targetUrlPatterns.filter(
                                    supportedMenuPattern
                                )
                                : [],
                            enabled: authored.enabled ?? true,
                            visible: authored.visible ?? true,
                            onclick: typeof authored.onclick === "function"
                                ? authored.onclick
                                : undefined,
                            authored
                        };
                    };
                    const serializedItems = () => Array.from(
                        items.values(),
                        (item) => ({
                            id: item.id,
                            ...(item.parentId === undefined
                                ? {}
                                : { parentId: item.parentId }),
                            type: item.type,
                            title: item.title,
                            contexts: item.contexts,
                            documentUrlPatterns:
                                item.documentUrlPatterns,
                            targetUrlPatterns: item.targetUrlPatterns,
                            enabled: item.enabled,
                            visible: item.visible
                        })
                    );
                    const postDefinitions = () => {
                        try {
                            port?.postMessage({
                                api: "contextMenus.replace",
                                items: serializedItems()
                            });
                        } catch {}
                    };
                    const queueValue = (map, key, value) => {
                        const queue = map.get(key) ?? [];
                        queue.push(value);
                        map.set(key, queue);
                    };
                    const authoredClickInfo = (item, nativeInfo, hit) => {
                        const info = {
                            ...nativeInfo,
                            menuItemId: item.originalID
                        };
                        const parent = item.parentId === undefined
                            ? undefined
                            : items.get(item.parentId);
                        if (parent) {
                            info.parentMenuItemId = parent.originalID;
                        }
                        if (!hit) return info;
                        info.pageUrl = hit.pageURL;
                        info.frameUrl = hit.documentURL;
                        info.editable = Boolean(hit.editable);
                        if (typeof hit.linkURL === "string") {
                            info.linkUrl = hit.linkURL;
                        }
                        if (typeof hit.sourceURL === "string") {
                            info.srcUrl = hit.sourceURL;
                        }
                        if (typeof hit.mediaType === "string") {
                            info.mediaType = hit.mediaType;
                        }
                        if (typeof hit.selectionText === "string") {
                            info.selectionText = hit.selectionText;
                        }
                        if (hit.mainFrame === true) info.frameId = 0;
                        else delete info.frameId;
                        return info;
                    };
                    const dispatchClick = (item, nativeInfo, tab, hit) => {
                        const info = authoredClickInfo(
                            item,
                            nativeInfo,
                            hit
                        );
                        try { item.onclick?.(info, tab); } catch {}
                        for (const listener of listeners) {
                            try { listener(info, tab); } catch {}
                        }
                    };
                    const flushClicks = (key) => {
                        const contexts = clickContexts.get(key) ?? [];
                        const events = nativeClicks.get(key) ?? [];
                        while (contexts.length > 0 && events.length > 0) {
                            const hit = contexts.shift();
                            const event = events.shift();
                            const { info, tab } = event;
                            globalThis.clearTimeout(
                                event.fallbackHandle
                            );
                            const item = items.get(key);
                            if (!item) continue;
                            dispatchClick(item, info, tab, hit);
                        }
                        if (contexts.length > 0) {
                            clickContexts.set(key, contexts);
                        } else {
                            clickContexts.delete(key);
                        }
                        if (events.length > 0) {
                            nativeClicks.set(key, events);
                        } else {
                            nativeClicks.delete(key);
                        }
                    };
                    const resumeNativeClicks = (key) => {
                        const item = items.get(key);
                        if (!item) return;
                        const needsWebpageHit = item.contexts.some(
                            (context) => context !== "tab"
                        );
                        if (!needsWebpageHit) {
                            const events = nativeClicks.get(key) ?? [];
                            nativeClicks.delete(key);
                            for (const event of events) {
                                globalThis.clearTimeout(event.fallbackHandle);
                                dispatchClick(item, event.info, event.tab);
                            }
                            return;
                        }
                        flushClicks(key);
                        if (
                            !item.contexts.includes("tab")
                            && !item.contexts.includes("all")
                        ) return;
                        for (const event of nativeClicks.get(key) ?? []) {
                            if (event.fallbackHandle !== undefined) continue;
                            event.fallbackHandle = globalThis.setTimeout(
                                () => {
                                    const pending = nativeClicks.get(key) ?? [];
                                    const index = pending.indexOf(event);
                                    if (index < 0) return;
                                    pending.splice(index, 1);
                                    if (pending.length > 0) {
                                        nativeClicks.set(key, pending);
                                    } else {
                                        nativeClicks.delete(key);
                                    }
                                    dispatchClick(
                                        items.get(key) ?? item,
                                        event.info,
                                        event.tab
                                    );
                                },
                                100
                            );
                        }
                    };
                    const receiveContextMenuMessage = (message) => {
                        if (
                            message?.api === "contextMenus.restore"
                            && Array.isArray(message.items)
                        ) {
                            const restoredItems = new Map();
                            for (const serialized of message.items) {
                                const originalID = decodedID(serialized?.id);
                                if (originalID === undefined) continue;
                                const parentId = serialized.parentId === undefined
                                    ? undefined
                                    : decodedID(serialized.parentId);
                                const item = definition(originalID, {
                                    type: serialized.type,
                                    title: serialized.title,
                                    contexts: serialized.contexts,
                                    documentUrlPatterns:
                                        serialized.documentUrlPatterns,
                                    targetUrlPatterns:
                                        serialized.targetUrlPatterns,
                                    enabled: serialized.enabled,
                                    visible: serialized.visible,
                                    ...(parentId === undefined
                                        ? {}
                                        : { parentId })
                                });
                                restoredItems.set(item.id, item);
                            }
                            items.clear();
                            for (const [id, item] of restoredItems) {
                                items.set(id, item);
                                resumeNativeClicks(id);
                            }
                            return;
                        }
                        if (
                            message?.api === "runtime.onInstalled"
                            && typeof message.eventID === "string"
                        ) {
                            if (!acknowledgedInstallEvents.has(message.eventID)) {
                                acknowledgedInstallEvents.add(message.eventID);
                                const details = { reason: message.reason };
                                if (typeof message.previousVersion === "string") {
                                    details.previousVersion =
                                        message.previousVersion;
                                }
                                pendingInstallDetails.push(details);
                                scheduleInstallDispatch();
                            }
                            try {
                                port?.postMessage({
                                    api: "runtime.onInstalled.ack",
                                    eventID: message.eventID
                                });
                            } catch {}
                            return;
                        }
                        if (
                            message?.api !== "contextMenus.click"
                            || typeof message.menuItemID !== "string"
                        ) {
                            return;
                        }
                        queueValue(
                            clickContexts,
                            message.menuItemID,
                            message
                        );
                        flushClicks(message.menuItemID);
                    };
                    const connectContextMenuTransport = () => {
                        if (port) return;
                        const runtime = nativeBrowser?.runtime
                            ?? primaryRoot?.runtime;
                        const connectNative = runtime?.connectNative;
                        if (typeof connectNative !== "function") return;
                        try {
                            port = Reflect.apply(
                                connectNative,
                                runtime,
                                [capabilityBrokerHost]
                            );
                        } catch {
                            port = undefined;
                            return;
                        }
                        port?.onMessage?.addListener(
                            receiveContextMenuMessage
                        );
                        port?.onDisconnect?.addListener(() => {
                            port = undefined;
                            globalThis.clearTimeout(reconnectHandle);
                            reconnectHandle = globalThis.setTimeout(
                                connectContextMenuTransport,
                                1000
                            );
                        });
                        try {
                            port?.postMessage({ api: "contextMenus.ready" });
                        } catch {}
                    };
                    const publishDefinitions = () => {
                        connectContextMenuTransport();
                        postDefinitions();
                    };
                    const nativeProperties = (item) => ({
                        ...item.authored,
                        id: item.id,
                        ...(item.parentId === undefined
                            ? { parentId: undefined }
                            : { parentId: item.parentId }),
                        contexts: ["tab"],
                        documentUrlPatterns: [],
                        targetUrlPatterns: [],
                        visible: true,
                        onclick: undefined
                    });
                    const nativeCreate = nativeMenus.create;
                    const nativeUpdate = nativeMenus.update;
                    const nativeRemove = nativeMenus.remove;
                    const nativeRemoveAll = nativeMenus.removeAll;
                    const create = (...args) => {
                        const properties = args[0] ?? {};
                        const originalID = properties.id
                            ?? `crest-generated-${++generatedID}`;
                        const item = definition(originalID, properties);
                        const nativeResult = Reflect.apply(
                            nativeCreate,
                            nativeMenus,
                            [nativeProperties(item), ...args.slice(1)]
                        );
                        items.set(item.id, item);
                        publishDefinitions();
                        return properties.id === undefined
                            ? nativeResult
                            : properties.id;
                    };
                    const update = (...args) => {
                        const key = encodedID(args[0]);
                        const existing = items.get(key);
                        if (!existing) {
                            return Reflect.apply(
                                nativeUpdate,
                                nativeMenus,
                                args
                            );
                        }
                        const item = definition(
                            existing.originalID,
                            args[1],
                            existing
                        );
                        const result = Reflect.apply(
                            nativeUpdate,
                            nativeMenus,
                            [item.id, nativeProperties(item), ...args.slice(2)]
                        );
                        items.set(key, item);
                        publishDefinitions();
                        return result;
                    };
                    const remove = (...args) => {
                        const key = encodedID(args[0]);
                        const result = Reflect.apply(
                            nativeRemove,
                            nativeMenus,
                            [key, ...args.slice(1)]
                        );
                        const removed = new Set([key]);
                        let changed = true;
                        while (changed) {
                            changed = false;
                            for (const item of items.values()) {
                                if (removed.has(item.parentId)) {
                                    changed = !removed.has(item.id) || changed;
                                    removed.add(item.id);
                                }
                            }
                        }
                        for (const id of removed) items.delete(id);
                        publishDefinitions();
                        return result;
                    };
                    const removeAll = (...args) => {
                        const result = Reflect.apply(
                            nativeRemoveAll,
                            nativeMenus,
                            args
                        );
                        items.clear();
                        publishDefinitions();
                        return result;
                    };
                    const onClicked = Object.freeze({
                        addListener(listener) {
                            if (typeof listener === "function") {
                                listeners.add(listener);
                            }
                        },
                        removeListener(listener) {
                            listeners.delete(listener);
                        },
                        hasListener(listener) {
                            return listeners.has(listener);
                        },
                        hasListeners() { return listeners.size > 0; }
                    });
                    try {
                        nativeMenus.onClicked?.addListener((info, tab) => {
                            const key = String(info?.menuItemId ?? "");
                            const event = { info, tab };
                            queueValue(nativeClicks, key, event);
                            resumeNativeClicks(key);
                        });
                    } catch {}
                    const installedOnClickedFacade = installEventFacade(
                        nativeMenus.onClicked,
                        onClicked
                    );
                    const overlays = new Map([
                        ["create", create],
                        ["update", update],
                        ["remove", remove],
                        ["removeAll", removeAll],
                        ["onClicked", onClicked]
                    ]);
                    if (installedOnClickedFacade) {
                        overlays.delete("onClicked");
                    }
                    for (const [property, value] of overlays) {
                        let descriptor;
                        try {
                            descriptor = Reflect.getOwnPropertyDescriptor(
                                nativeMenus,
                                property
                            );
                            Object.defineProperty(nativeMenus, property, {
                                value,
                                configurable: true,
                                enumerable: descriptor?.enumerable ?? true
                            });
                        } catch {}
                        try {
                            if (nativeMenus[property] === value) {
                                overlays.delete(property);
                            }
                        } catch {}
                    }
                    const normalized = overlays.size === 0
                        ? nativeMenus
                        : namespaceFacade(nativeMenus, {}, overlays);
                    connectContextMenuTransport();
                    normalizedMenuNamespaces.set(nativeMenus, normalized);
                    normalizedMenuNamespaces.set(normalized, normalized);
                    return normalized;
                };
                const isManifestOrigin = (value) =>
                    value === "<all_urls>"
                    || (typeof value === "string" && value.includes("://"));
                const requiredPermissionNames = new Set();
                const requiredOriginPatterns = new Set(
                    Array.isArray(declaredManifest.host_permissions)
                        ? declaredManifest.host_permissions
                        : []
                );
                for (const permission of (
                    Array.isArray(declaredManifest.permissions)
                        ? declaredManifest.permissions
                        : []
                )) {
                    if (isManifestOrigin(permission)) {
                        requiredOriginPatterns.add(permission);
                    } else {
                        requiredPermissionNames.add(permission);
                    }
                }
                const permissionRequestRemovesRequiredAccess = (request) => {
                    if (!request || typeof request !== "object") return false;
                    return (
                        Array.isArray(request.permissions)
                        && request.permissions.some((permission) =>
                            requiredPermissionNames.has(permission)
                        )
                    ) || (
                        Array.isArray(request.origins)
                        && request.origins.some((origin) =>
                            requiredOriginPatterns.has(origin)
                        )
                    );
                };
                const nativePermissionBoolean = (
                    nativePermissions,
                    nativeMethod,
                    request
                ) => new Promise((resolve) => {
                    let settled = false;
                    const settle = (value) => {
                        if (settled) return;
                        settled = true;
                        globalThis.clearTimeout(timeout);
                        resolve(Boolean(value));
                    };
                    // WebKit can start these operations without completing
                    // their callback or promise. Permissions are local state,
                    // so a bounded false result is safer than holding an
                    // extension's startup forever or issuing a destructive
                    // follow-up against state it never confirmed.
                    const timeout = globalThis.setTimeout(
                        () => settle(false),
                        250
                    );
                    if (typeof nativeMethod !== "function") {
                        settle(false);
                        return;
                    }
                    let returned;
                    try {
                        returned = Reflect.apply(
                            nativeMethod,
                            nativePermissions,
                            [request, (value) => settle(value)]
                        );
                    } catch {
                        settle(false);
                        return;
                    }
                    if (returned?.then instanceof Function) {
                        returned.then(
                            (value) => settle(value),
                            () => settle(false)
                        );
                    } else if (returned !== undefined) {
                        settle(returned);
                    }
                });
                const permissionCallbackOrPromise = (args, operation) => {
                    const callback = args.at(-1);
                    if (typeof callback === "function") {
                        operation.then(
                            (value) => callback(value),
                            () => callback(false)
                        );
                        return undefined;
                    }
                    return operation;
                };
                const normalizedPermissionNamespaces = new WeakMap();
                const normalizePermissionsNamespace = (nativePermissions) => {
                    if (!nativePermissions) return nativePermissions;
                    if (normalizedPermissionNamespaces.has(nativePermissions)) {
                        return normalizedPermissionNamespaces.get(
                            nativePermissions
                        );
                    }

                    let nativeContains;
                    let nativeRemove;
                    try {
                        nativeContains = nativePermissions.contains;
                        nativeRemove = nativePermissions.remove;
                    } catch {}
                    if (
                        typeof nativeContains !== "function"
                        || typeof nativeRemove !== "function"
                    ) {
                        normalizedPermissionNamespaces.set(
                            nativePermissions,
                            nativePermissions
                        );
                        return nativePermissions;
                    }

                    const containsOperation = (request) =>
                        nativePermissionBoolean(
                            nativePermissions,
                            nativeContains,
                            request
                        );
                    const contains = (...args) => permissionCallbackOrPromise(
                        args,
                        containsOperation(args[0])
                    );
                    const remove = (...args) => {
                        const request = args[0];
                        const operation = permissionRequestRemovesRequiredAccess(
                            request
                        )
                            ? Promise.resolve(false)
                            : containsOperation(request).then((isGranted) => {
                                if (!isGranted) return false;
                                return nativePermissionBoolean(
                                    nativePermissions,
                                    nativeRemove,
                                    request
                                );
                            });
                        return permissionCallbackOrPromise(args, operation);
                    };
                    const overlays = new Map([
                        ["contains", contains],
                        ["remove", remove]
                    ]);
                    for (const [methodName, method] of overlays) {
                        let descriptor;
                        try {
                            descriptor = Reflect.getOwnPropertyDescriptor(
                                nativePermissions,
                                methodName
                            );
                            Object.defineProperty(
                                nativePermissions,
                                methodName,
                                {
                                    value: method,
                                    configurable: true,
                                    enumerable: descriptor?.enumerable ?? true
                                }
                            );
                        } catch {}
                        try {
                            if (nativePermissions[methodName] === method) {
                                overlays.delete(methodName);
                            }
                        } catch {}
                    }
                    const normalized = overlays.size === 0
                        ? nativePermissions
                        : namespaceFacade(nativePermissions, {}, overlays);
                    normalizedPermissionNamespaces.set(
                        nativePermissions,
                        normalized
                    );
                    normalizedPermissionNamespaces.set(normalized, normalized);
                    return normalized;
                };
                const requestCapability = (
                    api,
                    payload,
                    args,
                    transform = (response) => response
                ) => {
                    const runtime = nativeBrowser?.runtime
                        ?? primaryRoot?.runtime;
                    const sendNativeMessage = runtime?.sendNativeMessage;
                    if (typeof sendNativeMessage !== "function") {
                        return rejectCallbackOrPromise(
                            args,
                            `Crest's ${api} capability is unavailable.`
                        );
                    }

                    const request = { api, ...payload };
                    const response = new Promise((resolve, reject) => {
                        let settled = false;
                        const settle = (operation, value) => {
                            if (settled) return;
                            settled = true;
                            operation(value);
                        };
                        let returned;
                        try {
                            returned = Reflect.apply(
                                sendNativeMessage,
                                runtime,
                                [capabilityBrokerHost, request]
                            );
                        } catch (error) {
                            settle(reject, error);
                            return;
                        }
                        if (returned?.then instanceof Function) {
                            returned.then(
                                (value) => settle(resolve, value),
                                (error) => settle(reject, error)
                            );
                        } else if (returned !== undefined) {
                            settle(resolve, returned);
                        } else {
                            settle(
                                reject,
                                new Error(
                                    `Crest's ${api} capability returned no response.`
                                )
                            );
                        }
                    }).then(transform);
                    const callback = args.at(-1);
                    if (typeof callback === "function") {
                        response.then(
                            (value) => callback(value),
                            () => callback(undefined)
                        );
                        return undefined;
                    }
                    return response;
                };
                const uncontrollableSetting = (effectiveValue) =>
                    Object.freeze({
                        onChange: noopEvent,
                        get(...args) {
                            return callbackOrPromise(args, {
                                value: effectiveValue,
                                levelOfControl: "not_controllable"
                            });
                        },
                        set(...args) {
                            return callbackOrPromise(args, undefined);
                        },
                        clear(...args) {
                            return callbackOrPromise(args, undefined);
                        }
                    });
                const extensionViews = () => {
                    for (const root of [nativeBrowser, nativeChrome]) {
                        const extensionNamespace = root?.extension;
                        if (typeof extensionNamespace?.getViews !== "function") {
                            continue;
                        }
                        try {
                            return Array.from(
                                extensionNamespace.getViews({ type: "popup" })
                            );
                        } catch {}
                    }
                    return [];
                };
                const serviceWorkerClients = Object.freeze({
                    async matchAll() {
                        return extensionViews().map((view) => ({
                            url: view.location?.href ?? "",
                            visibilityState:
                                view.document?.visibilityState ?? "hidden"
                        }));
                    }
                });
                if (!globalThis.clients) {
                    try {
                        Object.defineProperty(globalThis, "clients", {
                            value: serviceWorkerClients,
                            configurable: true
                        });
                    } catch {
                        try {
                            globalThis.clients = serviceWorkerClients;
                        } catch {}
                    }
                }
                // Worker code hosted in a background document keeps its
                // worker-lifecycle calls; answering them is harmless where
                // there is no waiting worker to skip.
                if (typeof globalThis.skipWaiting !== "function") {
                    const skipWaiting = () => Promise.resolve();
                    try {
                        Object.defineProperty(globalThis, "skipWaiting", {
                            value: skipWaiting,
                            configurable: true,
                            writable: true
                        });
                    } catch {
                        try { globalThis.skipWaiting = skipWaiting; } catch {}
                    }
                }

                const notificationListeners = Object.freeze({
                    clicked: new Set(),
                    buttonClicked: new Set(),
                    closed: new Set()
                });
                let notificationWatchPort;
                let notificationWatchReconnectHandle;
                const notificationListenerCount = () =>
                    Object.values(notificationListeners).reduce(
                        (count, listeners) => count + listeners.size,
                        0
                    );
                const publishNotificationEvent = (message) => {
                    if (
                        message?.api !== "notifications.event"
                        || typeof message.notificationIdentifier !== "string"
                    ) {
                        return;
                    }
                    let argumentsForListeners;
                    switch (message.kind) {
                    case "clicked":
                        argumentsForListeners = [
                            message.notificationIdentifier
                        ];
                        break;
                    case "buttonClicked":
                        if (!Number.isInteger(message.buttonIndex)) return;
                        argumentsForListeners = [
                            message.notificationIdentifier,
                            message.buttonIndex
                        ];
                        break;
                    case "closed":
                        argumentsForListeners = [
                            message.notificationIdentifier,
                            Boolean(message.byUser)
                        ];
                        break;
                    default:
                        return;
                    }
                    for (const listener of notificationListeners[message.kind]) {
                        try { listener(...argumentsForListeners); } catch {}
                    }
                };
                const connectNotificationWatch = () => {
                    if (
                        notificationWatchPort
                        || notificationListenerCount() === 0
                    ) {
                        return;
                    }
                    const runtime = nativeBrowser?.runtime
                        ?? primaryRoot?.runtime;
                    const connectNative = runtime?.connectNative;
                    if (typeof connectNative !== "function") return;
                    try {
                        notificationWatchPort = Reflect.apply(
                            connectNative,
                            runtime,
                            [capabilityBrokerHost]
                        );
                    } catch {
                        notificationWatchPort = undefined;
                        return;
                    }
                    notificationWatchPort?.onMessage?.addListener(
                        publishNotificationEvent
                    );
                    notificationWatchPort?.onDisconnect?.addListener(() => {
                        notificationWatchPort = undefined;
                        if (notificationListenerCount() === 0) return;
                        globalThis.clearTimeout(
                            notificationWatchReconnectHandle
                        );
                        notificationWatchReconnectHandle =
                            globalThis.setTimeout(
                                connectNotificationWatch,
                                1000
                            );
                    });
                    try {
                        notificationWatchPort?.postMessage({
                            api: "notifications.watch"
                        });
                    } catch {}
                };
                const notificationEvent = (kind) => Object.freeze({
                    addListener(listener) {
                        if (typeof listener !== "function") return;
                        notificationListeners[kind].add(listener);
                        connectNotificationWatch();
                    },
                    removeListener(listener) {
                        notificationListeners[kind].delete(listener);
                        if (notificationListenerCount() > 0) return;
                        globalThis.clearTimeout(
                            notificationWatchReconnectHandle
                        );
                        notificationWatchReconnectHandle = undefined;
                        const port = notificationWatchPort;
                        notificationWatchPort = undefined;
                        try { port?.disconnect(); } catch {}
                    },
                    hasListener(listener) {
                        return notificationListeners[kind].has(listener);
                    },
                    hasListeners() {
                        return notificationListeners[kind].size > 0;
                    }
                });
                const notifications = Object.freeze({
                    onClicked: notificationEvent("clicked"),
                    onButtonClicked: notificationEvent("buttonClicked"),
                    onClosed: notificationEvent("closed"),
                    onPermissionLevelChanged: noopEvent,
                    create(...args) {
                        const hasIdentifier = typeof args[0] === "string";
                        const options = args[hasIdentifier ? 1 : 0] ?? {};
                        const notificationIdentifier = hasIdentifier
                            ? args[0]
                            : `crest-${Date.now()}-${Math.random()
                                .toString(36).slice(2)}`;
                        return requestCapability(
                            "notifications.create",
                            {
                                notificationIdentifier,
                                title: String(options.title ?? ""),
                                message: String(options.message ?? ""),
                                buttonTitles: Array.isArray(options.buttons)
                                    ? options.buttons.map((button) =>
                                        String(button?.title ?? "")
                                    )
                                    : []
                            },
                            args,
                            (response) =>
                                response?.notificationIdentifier
                                    ?? notificationIdentifier
                        );
                    },
                    clear(...args) {
                        return requestCapability(
                            "notifications.clear",
                            {
                                notificationIdentifier: String(args[0] ?? "")
                            },
                            args,
                            (response) => Boolean(response?.cleared)
                        );
                    },
                    getAll(...args) {
                        return requestCapability(
                            "notifications.getAll",
                            {},
                            args,
                            (response) => Object.fromEntries(
                                Array.isArray(
                                    response?.notificationIdentifiers
                                )
                                    ? response.notificationIdentifiers.map(
                                        (identifier) => [identifier, true]
                                    )
                                    : []
                            )
                        );
                    },
                    getPermissionLevel(...args) {
                        return requestCapability(
                            "notifications.getPermissionLevel",
                            {},
                            args,
                            (response) => response?.level === "granted"
                                ? "granted"
                                : "denied"
                        );
                    },
                    update(...args) {
                        const options = args[1] ?? {};
                        return requestCapability(
                            "notifications.update",
                            {
                                notificationIdentifier:
                                    String(args[0] ?? ""),
                                title: String(options.title ?? ""),
                                message: String(options.message ?? ""),
                                buttonTitles: Array.isArray(options.buttons)
                                    ? options.buttons.map((button) =>
                                        String(button?.title ?? "")
                                    )
                                    : []
                            },
                            args,
                            (response) => Boolean(response?.updated)
                        );
                    },
                });
                const action = {
                    getUserSettings(...args) {
                        return callbackOrPromise(args, { isOnToolbar: false });
                    }
                };
                const permissions = {
                    addHostAccessRequest(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "Host-access requests are not connected to Crest yet."
                        );
                    },
                    removeHostAccessRequest(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "Host-access requests are not connected to Crest yet."
                        );
                    }
                };
                const privacyServices = {
                    passwordSavingEnabled: uncontrollableSetting(true),
                    autofillEnabled: uncontrollableSetting(false),
                    autofillCreditCardEnabled: uncontrollableSetting(false),
                    autofillAddressEnabled: uncontrollableSetting(false)
                };
                const storageManaged = {
                    onChanged: noopEvent,
                    get(...args) { return callbackOrPromise(args, {}); },
                    getBytesInUse(...args) {
                        return callbackOrPromise(args, 0);
                    }
                };
                let offscreenFrame;
                let offscreenReady;
                const offscreen = {
                    Reason: Object.freeze({
                        AUDIO_PLAYBACK: "AUDIO_PLAYBACK",
                        BLOBS: "BLOBS",
                        CLIPBOARD: "CLIPBOARD",
                        DISPLAY_MEDIA: "DISPLAY_MEDIA",
                        DOM_PARSER: "DOM_PARSER",
                        DOM_SCRAPING: "DOM_SCRAPING",
                        GEOLOCATION: "GEOLOCATION",
                        IFRAME_SCRIPTING: "IFRAME_SCRIPTING",
                        LOCAL_STORAGE: "LOCAL_STORAGE",
                        MATCH_MEDIA: "MATCH_MEDIA",
                        USER_MEDIA: "USER_MEDIA",
                        WEB_RTC: "WEB_RTC",
                        WORKERS: "WORKERS"
                    }),
                    createDocument(...args) {
                        const options = args[0];
                        const url = options?.url;
                        if (typeof document === "undefined" || !url) {
                            return rejectCallbackOrPromise(
                                args,
                                "An offscreen document requires a background page and URL."
                            );
                        }
                        if (!offscreenReady) {
                            offscreenFrame = document.createElement("iframe");
                            offscreenFrame.hidden = true;
                            offscreenFrame.src = primaryRoot.runtime.getURL(url);
                            offscreenReady = new Promise((resolve, reject) => {
                                offscreenFrame.addEventListener(
                                    "load",
                                    resolve,
                                    { once: true }
                                );
                                offscreenFrame.addEventListener(
                                    "error",
                                    reject,
                                    { once: true }
                                );
                                (document.body ?? document.documentElement)
                                    .append(offscreenFrame);
                            });
                        }
                        const callback = args.at(-1);
                        if (typeof callback === "function") {
                            offscreenReady.then(() => callback(), () => callback());
                        }
                        return offscreenReady;
                    },
                    closeDocument(...args) {
                        offscreenFrame?.remove();
                        offscreenFrame = undefined;
                        offscreenReady = undefined;
                        return callbackOrPromise(args);
                    },
                    hasDocument(...args) {
                        return callbackOrPromise(args, Boolean(offscreenFrame));
                    }
                };
                const management = {
                    onEnabled: noopEvent,
                    onDisabled: noopEvent,
                    onInstalled: noopEvent,
                    onUninstalled: noopEvent,
                    getSelf(...args) {
                        const manifest = primaryRoot.runtime.getManifest();
                        return callbackOrPromise(args, {
                            id: primaryRoot.runtime.id,
                            name: manifest.name,
                            version: manifest.version,
                            enabled: true,
                            type: "extension"
                        });
                    },
                    getAll(...args) { return callbackOrPromise(args, []); },
                    setEnabled(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "Extensions cannot change another extension in Crest."
                        );
                    }
                };
                const downloads = {
                    onChanged: noopEvent,
                    onCreated: noopEvent,
                    onDeterminingFilename: noopEvent,
                    onErased: noopEvent,
                    download(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "Downloads are not available in this WebKit extension."
                        );
                    }
                };
                const sidePanel = {
                    setPanelBehavior(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "Side panels are not available in Crest."
                        );
                    }
                };
                const idleStateChangeListeners = new Set();
                let idleDetectionIntervalInSeconds = 60;
                let idleWatchPort;
                let idleWatchReconnectHandle;
                const isIdleState = (state) =>
                    state === "active"
                    || state === "idle"
                    || state === "locked";
                const publishIdleStateChange = (message) => {
                    const state = message?.state;
                    if (!isIdleState(state)) return;
                    for (const listener of idleStateChangeListeners) {
                        try { listener(state); } catch {}
                    }
                };
                const postIdleWatchConfiguration = () => {
                    try {
                        idleWatchPort?.postMessage({
                            api: "idle.watch",
                            detectionIntervalInSeconds:
                                idleDetectionIntervalInSeconds
                        });
                    } catch {}
                };
                const connectIdleWatch = () => {
                    if (
                        idleWatchPort
                        || idleStateChangeListeners.size === 0
                    ) {
                        return;
                    }
                    const runtime = nativeBrowser?.runtime
                        ?? primaryRoot?.runtime;
                    const connectNative = runtime?.connectNative;
                    if (typeof connectNative !== "function") return;
                    try {
                        idleWatchPort = Reflect.apply(
                            connectNative,
                            runtime,
                            [capabilityBrokerHost]
                        );
                    } catch {
                        idleWatchPort = undefined;
                        return;
                    }
                    idleWatchPort?.onMessage?.addListener(
                        publishIdleStateChange
                    );
                    idleWatchPort?.onDisconnect?.addListener(() => {
                        idleWatchPort = undefined;
                        if (idleStateChangeListeners.size === 0) return;
                        globalThis.clearTimeout(idleWatchReconnectHandle);
                        idleWatchReconnectHandle = globalThis.setTimeout(
                            connectIdleWatch,
                            1000
                        );
                    });
                    postIdleWatchConfiguration();
                };
                const idleStateChangedEvent = Object.freeze({
                    addListener(listener) {
                        if (typeof listener !== "function") return;
                        idleStateChangeListeners.add(listener);
                        connectIdleWatch();
                    },
                    removeListener(listener) {
                        idleStateChangeListeners.delete(listener);
                        if (idleStateChangeListeners.size > 0) return;
                        globalThis.clearTimeout(idleWatchReconnectHandle);
                        idleWatchReconnectHandle = undefined;
                        const port = idleWatchPort;
                        idleWatchPort = undefined;
                        try { port?.disconnect(); } catch {}
                    },
                    hasListener(listener) {
                        return idleStateChangeListeners.has(listener);
                    },
                    hasListeners() {
                        return idleStateChangeListeners.size > 0;
                    }
                });
                const idle = {
                    onStateChanged: idleStateChangedEvent,
                    queryState(...args) {
                        const detectionIntervalInSeconds = Number(args[0]);
                        if (
                            !Number.isFinite(detectionIntervalInSeconds)
                            || detectionIntervalInSeconds < 0
                        ) {
                            return rejectCallbackOrPromise(
                                args,
                                "idle.queryState requires a nonnegative interval."
                            );
                        }
                        return requestCapability(
                            "idle.queryState",
                            { detectionIntervalInSeconds },
                            args,
                            (response) => {
                                const state = response?.state;
                                if (!isIdleState(state)) {
                                    throw new Error(
                                        "Crest returned an invalid idle state."
                                    );
                                }
                                return state;
                            }
                        );
                    },
                    setDetectionInterval(interval) {
                        const value = Number(interval);
                        if (!Number.isFinite(value) || value < 0) {
                            throw new TypeError(
                                "idle.setDetectionInterval requires a nonnegative interval."
                            );
                        }
                        idleDetectionIntervalInSeconds = value;
                        if (idleStateChangeListeners.size > 0) {
                            connectIdleWatch();
                            postIdleWatchConfiguration();
                        }
                    }
                };
                const webRequest = {
                    onAuthRequired: noopEvent,
                    handlerBehaviorChanged(...args) {
                        return callbackOrPromise(args);
                    }
                };
                const webNavigation = {
                    onCreatedNavigationTarget: noopEvent,
                    onHistoryStateUpdated: noopEvent,
                    onTabReplaced: noopEvent
                };
                const runtime = {
                    id: extensionID,
                    onUpdateAvailable: noopEvent,
                    getURL(path = "") {
                        return fallbackResourceURL(path);
                    },
                    getManifest() {
                        return declaredManifest;
                    },
                    requestUpdateCheck(...args) {
                        const callback = args.at(-1);
                        if (typeof callback === "function") {
                            queueMicrotask(() => callback("no_update"));
                        }
                        return Promise.resolve({ status: "no_update" });
                    }
                };
                const fallbacksFor = (nativeRoot) => ({
                    action,
                    browserAction: action,
                    permissions,
                    privacy: { services: privacyServices },
                    storage: { managed: storageManaged },
                    notifications,
                    offscreen,
                    management,
                    downloads,
                    sidePanel,
                    idle,
                    webRequest,
                    webNavigation,
                    runtime
                });
                const installFallbacks = (
                    nativeValue,
                    fallbacks,
                    pinExisting = true
                ) => {
                    if (!nativeValue) return;

                    for (const [property, fallback] of Object.entries(fallbacks)) {
                        let existing;
                        try { existing = nativeValue[property]; } catch { continue; }

                        if (existing === undefined) {
                            try {
                                Object.defineProperty(nativeValue, property, {
                                    value: fallback,
                                    writable: false,
                                    configurable: false,
                                    enumerable: true
                                });
                            } catch {
                                try { nativeValue[property] = fallback; } catch {}
                            }
                        } else {
                            try {
                                const descriptor =
                                    Reflect.getOwnPropertyDescriptor(
                                        nativeValue,
                                        property
                                    );
                                if (pinExisting && descriptor?.configurable) {
                                    Object.defineProperty(
                                        nativeValue,
                                        property,
                                        {
                                            value: existing,
                                            writable:
                                                descriptor.writable ?? false,
                                            configurable: false,
                                            enumerable:
                                                descriptor.enumerable ?? true
                                        }
                                    );
                                }
                            } catch {}
                            if (
                                fallback
                                && typeof fallback === "object"
                                && (typeof existing === "object"
                                    || typeof existing === "function")
                            ) {
                                installFallbacks(
                                    existing,
                                    fallback,
                                    pinExisting
                                );
                            }
                        }
                    }
                };
                const installCompatibility = (nativeRoot) => {
                    if (!nativeRoot) return;

                    normalizeRuntime(nativeRoot.runtime);
                    const normalizedI18n = normalizeI18n(nativeRoot.i18n);
                    if (
                        normalizedI18n
                        && normalizedI18n !== nativeRoot.i18n
                    ) {
                        try {
                            Object.defineProperty(nativeRoot, "i18n", {
                                value: normalizedI18n,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try { nativeRoot.i18n = normalizedI18n; } catch {}
                        }
                    }
                    for (const property of ["menus", "contextMenus"]) {
                        let nativeMenus;
                        try { nativeMenus = nativeRoot[property]; } catch {}
                        if (!nativeMenus) continue;
                        const normalizedMenus = normalizeMenuNamespace(
                            nativeMenus
                        );
                        if (normalizedMenus === nativeMenus) continue;
                        try {
                            Object.defineProperty(nativeRoot, property, {
                                value: normalizedMenus,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot[property] = normalizedMenus;
                            } catch {}
                        }
                    }
                    let nativePermissions;
                    try {
                        nativePermissions = nativeRoot.permissions;
                    } catch {}
                    const normalizedPermissions =
                        normalizePermissionsNamespace(nativePermissions);
                    if (
                        normalizedPermissions
                        && normalizedPermissions !== nativePermissions
                    ) {
                        try {
                            Object.defineProperty(nativeRoot, "permissions", {
                                value: normalizedPermissions,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot.permissions = normalizedPermissions;
                            } catch {}
                        }
                    }
                    const { runtime: runtimeFallback, ...fallbacks } =
                        fallbacksFor(nativeRoot);
                    installFallbacks(nativeRoot, fallbacks);
                    installFallbacks(
                        nativeRoot.runtime,
                        runtimeFallback,
                        false
                    );
                    if (nativeRoot.runtime) {
                        try {
                            Object.defineProperty(
                                nativeRoot.runtime,
                                "getManifest",
                                {
                                    value: () => declaredManifest,
                                    configurable: true
                                }
                            );
                        } catch {}
                    }
                    return nativeRoot;
                };
                const namespaceFacade = (
                    nativeValue,
                    fallback,
                    explicitOverlays = new Map()
                ) => {
                    if (nativeValue === undefined || nativeValue === null) {
                        return fallback;
                    }
                    if (
                        (!fallback
                            || typeof fallback !== "object"
                            || Object.keys(fallback).length === 0)
                        && explicitOverlays.size === 0
                    ) {
                        return nativeValue;
                    }
                    if (
                        typeof nativeValue !== "object"
                        && typeof nativeValue !== "function"
                    ) {
                        return nativeValue;
                    }

                    const fallbackValues = new Map(
                        Object.entries(fallback ?? {})
                    );
                    const boundMethods = new Map();
                    const nestedFacades = new Map();
                    const resolvedValue = (property) => {
                        if (explicitOverlays.has(property)) {
                            return explicitOverlays.get(property);
                        }
                        let value;
                        try {
                            value = Reflect.get(
                                nativeValue,
                                property,
                                nativeValue
                            );
                        } catch {}
                        const fallbackValue = fallbackValues.get(property);
                        if (value === undefined) return fallbackValue;
                        if (
                            fallbackValues.has(property)
                            && fallbackValue
                            && typeof fallbackValue === "object"
                            && (typeof value === "object"
                                || typeof value === "function")
                        ) {
                            const cached = nestedFacades.get(property);
                            if (cached?.nativeValue === value) {
                                return cached.facade;
                            }
                            const facade = namespaceFacade(
                                value,
                                fallbackValue
                            );
                            nestedFacades.set(property, {
                                nativeValue: value,
                                facade
                            });
                            return facade;
                        }
                        if (typeof value !== "function") return value;
                        const cached = boundMethods.get(property);
                        if (cached?.nativeValue === value) {
                            return cached.bound;
                        }
                        const bound = value.bind(nativeValue);
                        boundMethods.set(property, {
                            nativeValue: value,
                            bound
                        });
                        return bound;
                    };
                    return new Proxy(Object.create(null), {
                        get(_, property) {
                            return resolvedValue(property);
                        },
                        set(_, property, value) {
                            try {
                                return Reflect.set(
                                    nativeValue,
                                    property,
                                    value,
                                    nativeValue
                                );
                            } catch {
                                return false;
                            }
                        },
                        has(_, property) {
                            return explicitOverlays.has(property)
                                || fallbackValues.has(property)
                                || property in nativeValue;
                        },
                        ownKeys() {
                            const keys = new Set(
                                Reflect.ownKeys(nativeValue)
                            );
                            for (const property of fallbackValues.keys()) {
                                keys.add(property);
                            }
                            for (const property of explicitOverlays.keys()) {
                                keys.add(property);
                            }
                            return Array.from(keys);
                        },
                        getOwnPropertyDescriptor(_, property) {
                            if (!explicitOverlays.has(property)
                                && !fallbackValues.has(property)
                                && !(property in nativeValue)) {
                                return undefined;
                            }
                            let nativeDescriptor;
                            try {
                                nativeDescriptor =
                                    Reflect.getOwnPropertyDescriptor(
                                        nativeValue,
                                        property
                                    );
                            } catch {}
                            return {
                                value: resolvedValue(property),
                                writable: true,
                                configurable: true,
                                enumerable:
                                    nativeDescriptor?.enumerable ?? true
                            };
                        }
                    });
                };
                const nativeCapabilityNames = [
                    "action", "alarms", "bookmarks", "browserAction",
                    "commands", "contentScripts", "contextMenus", "cookies",
                    "declarativeNetRequest", "devtools", "downloads",
                    "extension", "history", "i18n", "identity", "idle",
                    "management", "notifications", "offscreen", "omnibox",
                    "pageAction", "permissions", "privacy", "runtime",
                    "scripting", "sessions", "sidePanel", "storage", "tabs",
                    "topSites", "webNavigation", "webRequest", "windows"
                ];
                const installNativeAliases = (target, source) => {
                    if (!target || !source || target === source) return;
                    for (const property of nativeCapabilityNames) {
                        let current;
                        let nativeValue;
                        try {
                            current = target[property];
                            nativeValue = source[property];
                        } catch {
                            continue;
                        }
                        if (current !== undefined || nativeValue === undefined) {
                            continue;
                        }
                        try {
                            Object.defineProperty(target, property, {
                                value: nativeValue,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {}
                    }
                };
                installNativeAliases(nativeChrome, nativeBrowser);
                installNativeAliases(nativeBrowser, nativeChrome);
                const installedRoots = new Set();
                for (const root of [nativeChrome, nativeBrowser]) {
                    if (!root || installedRoots.has(root)) continue;
                    installedRoots.add(root);
                    installCompatibility(root);
                }
                const installNamespaceFacades = (root, alternateRoot) => {
                    if (!root) return;
                    const fallbacks = fallbacksFor(root);
                    for (const property of nativeCapabilityNames) {
                        if (property === "runtime") continue;
                        let nativeValue;
                        try { nativeValue = root[property]; } catch {}
                        if (nativeValue === undefined && alternateRoot) {
                            try {
                                nativeValue = alternateRoot[property];
                            } catch {}
                        }
                        const fallback = fallbacks[property];
                        if (fallback === undefined) continue;
                        let facade = namespaceFacade(nativeValue, fallback);
                        if (facade === nativeValue) continue;
                        try {
                            Object.defineProperty(root, property, {
                                get() { return facade; },
                                set(value) {
                                    nativeValue = value;
                                    facade = namespaceFacade(
                                        nativeValue,
                                        fallback
                                    );
                                },
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try { root[property] = facade; } catch {}
                        }
                    }
                };
                installNamespaceFacades(nativeChrome, nativeBrowser);
                installNamespaceFacades(nativeBrowser, nativeChrome);
                const installMissingRoot = (name, root) => {
                    if (!root || globalThis[name] !== undefined) return;
                    try {
                        Object.defineProperty(globalThis, name, {
                            value: root,
                            configurable: true
                        });
                    } catch {
                        try { globalThis[name] = root; } catch {}
                    }
                };
                installMissingRoot("chrome", nativeBrowser);
                installMissingRoot("browser", nativeChrome);
                const rootFacadeCache = new WeakMap();
                const rootFacade = (root, alternateRoot) => {
                    if (!root) return root;
                    if (rootFacadeCache.has(root)) {
                        return rootFacadeCache.get(root);
                    }
                    const overlays = new Map();
                    const currentNamespace = (property) => {
                        let value;
                        try { value = root[property]; } catch {}
                        if (value === undefined && alternateRoot) {
                            try { value = alternateRoot[property]; } catch {}
                        }
                        return value;
                    };

                    const nativeI18n = currentNamespace("i18n");
                    const normalizedI18n = normalizeI18n(nativeI18n);
                    if (normalizedI18n !== nativeI18n) {
                        overlays.set("i18n", normalizedI18n);
                    }
                    for (const property of ["menus", "contextMenus"]) {
                        const nativeMenus = currentNamespace(property);
                        const normalizedMenus = normalizeMenuNamespace(
                            nativeMenus
                        );
                        if (normalizedMenus !== nativeMenus) {
                            overlays.set(property, normalizedMenus);
                        }
                    }
                    const nativePermissions = currentNamespace("permissions");
                    const normalizedPermissions =
                        normalizePermissionsNamespace(nativePermissions);
                    if (normalizedPermissions !== nativePermissions) {
                        overlays.set("permissions", normalizedPermissions);
                    }
                    const nativeRuntime = currentNamespace("runtime");
                    if (
                        nativeRuntime
                        && Object.keys(runtime).some((property) => {
                            try {
                                return nativeRuntime[property] === undefined;
                            } catch {
                                return true;
                            }
                        })
                    ) {
                        overlays.set(
                            "runtime",
                            namespaceFacade(nativeRuntime, runtime)
                        );
                    }
                    const facade = overlays.size === 0
                        ? root
                        : namespaceFacade(root, {}, overlays);
                    rootFacadeCache.set(root, facade);
                    return facade;
                };
                const installRootFacade = (name, root, alternateRoot) => {
                    if (!root) return;
                    const facade = rootFacade(root, alternateRoot);
                    if (facade === root) return;
                    try {
                        Object.defineProperty(globalThis, name, {
                            value: facade,
                            configurable: true
                        });
                    } catch {
                        try { globalThis[name] = facade; } catch {}
                    }
                };
                installRootFacade(
                    "chrome",
                    globalThis.chrome,
                    globalThis.browser
                );
                installRootFacade(
                    "browser",
                    globalThis.browser,
                    globalThis.chrome
                );
            })();
            """
    }

}

typealias BrowserChromeWebStoreCompatibilityPackagePreparer =
    BrowserWebExtensionCompatibilityPackagePreparer
