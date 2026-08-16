import CryptoKit
import Foundation

struct BrowserWebExtensionCompatibilityPackagePreparer {
    private static let legacyBackgroundPreludePattern =
        #"(?s)\A// Crest's WKWebExtension host currently has no notifications API\.\s*.*?Object\.defineProperty\(globalThis, \"chrome\", \{\s*value: crestChromeCompatibility,\s*configurable: true\s*\}\);\s*\}\s*"#
    private static let emulatedPermissions: Set<String> = [
        "downloads",
        "history",
        "identity",
        "idle",
        "management",
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
            let isModule = background["type"] as? String == "module"
            let backgroundBootstrapName = try installServiceWorkerBootstrap(
                in: resourceURL,
                serviceWorker: serviceWorker,
                isModule: isModule,
                compatibilityScriptName: compatibilityScriptName
            )
            background["service_worker"] = backgroundBootstrapName
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
        isModule: Bool,
        compatibilityScriptName: String
    ) throws -> String {
        let compatibilitySpecifier = Self.javascriptStringLiteral(
            "./\(compatibilityScriptName)"
        )
        let workerSpecifier = Self.javascriptStringLiteral("./\(serviceWorker)")
        let backgroundBootstrap =
            if isModule {
                "import \(compatibilitySpecifier);\nimport \(workerSpecifier);"
            } else {
                "importScripts(\(compatibilitySpecifier), \(workerSpecifier));"
            }
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

    static func requiresCompatibilityLayer(
        requestedPermissions: [String]
    ) -> Bool {
        !emulatedPermissions.isDisjoint(with: requestedPermissions)
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
        var source = try String(contentsOf: pageURL, encoding: .utf8)
        let compatibilityTag =
            #"<script src="/\#(compatibilityScriptName)"></script>"#
        var tags: [String] = []
        if !source.contains(compatibilityTag) {
            tags.append(compatibilityTag)
        }
        guard !tags.isEmpty else { return false }
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
        let digest = SHA256.hash(data: Data(source.utf8))
        let fingerprint = digest.prefix(8).map {
            String(format: "%02x", $0)
        }.joined()
        return "\(prefix)-\(fingerprint).js"
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
                const fallbackResourceURL = (path = "") => new URL(
                    String(path),
                    extensionBaseURL
                ).href;

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

                const normalizedI18nNamespaces = new WeakSet();
                const normalizeI18n = (nativeI18n) => {
                    if (!nativeI18n || normalizedI18nNamespaces.has(nativeI18n)) {
                        return;
                    }
                    normalizedI18nNamespaces.add(nativeI18n);

                    let nativeGetMessage;
                    let descriptor;
                    try {
                        nativeGetMessage = nativeI18n.getMessage;
                        descriptor = Reflect.getOwnPropertyDescriptor(
                            nativeI18n,
                            "getMessage"
                        );
                    } catch {}
                    if (typeof nativeGetMessage !== "function") return;
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

                const notifications = Object.freeze({
                    onClicked: noopEvent,
                    onButtonClicked: noopEvent,
                    onClosed: noopEvent,
                    onPermissionLevelChanged: noopEvent,
                    create(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "Extension notifications are not connected to Crest yet."
                        );
                    },
                    clear(...args) { return callbackOrPromise(args, false); },
                    getAll(...args) { return callbackOrPromise(args, {}); },
                    getPermissionLevel(...args) {
                        return callbackOrPromise(args, "denied");
                    },
                    update(...args) { return callbackOrPromise(args, false); }
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
                const idle = {
                    onStateChanged: noopEvent,
                    queryState(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "System idle state is not connected to Crest yet."
                        );
                    },
                    setDetectionInterval() {}
                };
                const webRequest = { onAuthRequired: noopEvent };
                const webNavigation = {
                    onCreatedNavigationTarget: noopEvent,
                    onHistoryStateUpdated: noopEvent,
                    onTabReplaced: noopEvent
                };
                const runtime = {
                    id: extensionID,
                    getURL(path = "") {
                        return fallbackResourceURL(path);
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
                    idle,
                    webRequest,
                    webNavigation,
                    runtime
                });
                const installFallbacks = (nativeValue, fallbacks) => {
                    if (!nativeValue) return;

                    for (const [property, fallback] of Object.entries(fallbacks)) {
                        let existing;
                        try { existing = nativeValue[property]; } catch { continue; }

                        if (existing === undefined) {
                            try {
                                Object.defineProperty(nativeValue, property, {
                                    value: fallback,
                                    configurable: true,
                                    enumerable: true
                                });
                            } catch {
                                try { nativeValue[property] = fallback; } catch {}
                            }
                        } else if (
                            fallback
                            && typeof fallback === "object"
                            && (typeof existing === "object"
                                || typeof existing === "function")
                        ) {
                            installFallbacks(existing, fallback);
                        }
                    }
                };
                const installCompatibility = (nativeRoot) => {
                    if (!nativeRoot) return;

                    normalizeRuntime(nativeRoot.runtime);
                    normalizeI18n(nativeRoot.i18n);
                    const { runtime: runtimeFallback, ...fallbacks } =
                        fallbacksFor(nativeRoot);
                    installFallbacks(nativeRoot, fallbacks);
                    installFallbacks(nativeRoot.runtime, runtimeFallback);
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
                const namespaceFacade = (nativeValue, fallback) => {
                    if (nativeValue === undefined || nativeValue === null) {
                        return fallback;
                    }
                    if (
                        !fallback
                        || typeof fallback !== "object"
                        || (typeof nativeValue !== "object"
                            && typeof nativeValue !== "function")
                    ) {
                        return nativeValue;
                    }

                    const overlays = new Map();
                    for (const [property, fallbackValue] of
                        Object.entries(fallback)) {
                        let existing;
                        try { existing = nativeValue[property]; } catch {}
                        if (existing === undefined) {
                            overlays.set(property, fallbackValue);
                            continue;
                        }
                        if (
                            fallbackValue
                            && typeof fallbackValue === "object"
                            && (typeof existing === "object"
                                || typeof existing === "function")
                        ) {
                            const nested = namespaceFacade(
                                existing,
                                fallbackValue
                            );
                            if (nested !== existing) {
                                overlays.set(property, nested);
                            }
                        }
                    }
                    if (overlays.size === 0) return nativeValue;

                    const boundMethods = new Map();
                    return new Proxy(Object.create(null), {
                        get(_, property) {
                            if (overlays.has(property)) {
                                return overlays.get(property);
                            }
                            let value;
                            try {
                                value = Reflect.get(
                                    nativeValue,
                                    property,
                                    nativeValue
                                );
                            } catch {
                                return undefined;
                            }
                            if (typeof value !== "function") return value;
                            if (!boundMethods.has(property)) {
                                boundMethods.set(
                                    property,
                                    value.bind(nativeValue)
                                );
                            }
                            return boundMethods.get(property);
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
                            return overlays.has(property)
                                || property in nativeValue;
                        },
                        ownKeys() {
                            const keys = new Set(
                                Reflect.ownKeys(nativeValue)
                            );
                            for (const property of overlays.keys()) {
                                keys.add(property);
                            }
                            return Array.from(keys);
                        },
                        getOwnPropertyDescriptor(_, property) {
                            if (!overlays.has(property)
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
                                value: overlays.has(property)
                                    ? overlays.get(property)
                                    : Reflect.get(
                                        nativeValue,
                                        property,
                                        nativeValue
                                    ),
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
                        const facade = namespaceFacade(nativeValue, fallback);
                        if (facade === nativeValue) continue;
                        try {
                            Object.defineProperty(root, property, {
                                value: facade,
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
            })();
            """
    }

}

typealias BrowserChromeWebStoreCompatibilityPackagePreparer =
    BrowserWebExtensionCompatibilityPackagePreparer
