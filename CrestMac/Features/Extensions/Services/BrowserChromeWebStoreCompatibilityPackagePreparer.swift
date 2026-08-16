import Foundation

struct BrowserChromeWebStoreCompatibilityPackagePreparer {
    private static let compatibilityScriptName =
        "crest-webextension-compatibility.js"
    private static let backgroundPageName =
        "crest-webextension-background.html"
    private static let backgroundBootstrapName =
        "crest-webextension-background-bootstrap.js"
    private static let backgroundMarkerName =
        "crest-webextension-background-marker.js"
    private static let backgroundMarkerScript =
        "globalThis.__crestIsWebExtensionBackground = true;"
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
    ) throws -> BrowserChromeWebStorePreparedPackage? {
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
                throw BrowserChromeWebStoreCompatibilityPackageError
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
            throw BrowserChromeWebStoreCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let compatibilityScript = try Self.webExtensionCompatibilityScript(
            manifest: manifest,
            runtimeIdentity: runtimeIdentity
        )
        try compatibilityScript.write(
            to: resourceURL.appending(path: Self.compatibilityScriptName),
            atomically: true,
            encoding: .utf8
        )
        try Self.backgroundMarkerScript.write(
            to: resourceURL.appending(path: Self.backgroundMarkerName),
            atomically: true,
            encoding: .utf8
        )
        var installed = try installBackgroundCompatibility(
            in: resourceURL,
            manifest: &manifest,
            compatibilityScript: compatibilityScript
        )
        installed =
            try installExtensionPageCompatibility(
                in: resourceURL,
                manifest: manifest
            ) || installed
        installed =
            Self.installContentScriptCompatibility(in: &manifest)
            || installed

        guard installed else {
            try? fileManager.removeItem(
                at: resourceURL.appending(path: Self.compatibilityScriptName)
            )
            try? fileManager.removeItem(
                at: resourceURL.appending(path: Self.backgroundMarkerName)
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
        compatibilityScript: String
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
            if background["type"] as? String == "module" {
                try installModuleBackgroundPage(
                    in: resourceURL,
                    serviceWorker: serviceWorker
                )
                manifest["background"] = [
                    "page": Self.backgroundPageName,
                    "persistent": false,
                ]
            } else {
                try (
                    Self.backgroundMarkerScript
                    + "\n"
                    + compatibilityScript
                    + "\n\n"
                    + originalWorker
                ).write(
                    to: workerURL,
                    atomically: true,
                    encoding: .utf8
                )
            }
            return true
        }

        if var scripts = background["scripts"] as? [String] {
            if !scripts.contains(Self.backgroundMarkerName) {
                scripts.insert(Self.backgroundMarkerName, at: 0)
            }
            if !scripts.contains(Self.compatibilityScriptName) {
                let markerIndex = scripts.firstIndex(
                    of: Self.backgroundMarkerName
                ) ?? 0
                scripts.insert(
                    Self.compatibilityScriptName,
                    at: markerIndex + 1
                )
            }
            background["scripts"] = scripts
            manifest["background"] = background
            return true
        }

        if let page = background["page"] as? String {
            return try injectCompatibilityScript(
                into: page,
                in: resourceURL,
                marksBackground: true
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

    private func installModuleBackgroundPage(
        in resourceURL: URL,
        serviceWorker: String
    ) throws {
        let workerSpecifier = Self.javascriptStringLiteral(
            "./\(serviceWorker)"
        )
        let backgroundBootstrap =
            """
            import(\(workerSpecifier)).finally(() => {
                globalThis
                    .__crestCompleteWebExtensionBackgroundBootstrap?.();
            });
            """
        try backgroundBootstrap.write(
            to: resourceURL.appending(path: Self.backgroundBootstrapName),
            atomically: true,
            encoding: .utf8
        )
        let backgroundPage =
            """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <script src="\(Self.backgroundMarkerName)"></script>
              <script src="\(Self.compatibilityScriptName)"></script>
              <script type="module" src="\(Self.backgroundBootstrapName)"></script>
            </head>
            <body></body>
            </html>
            """
        try backgroundPage.write(
            to: resourceURL.appending(path: Self.backgroundPageName),
            atomically: true,
            encoding: .utf8
        )
    }

    static func requiresCompatibilityLayer(
        requestedPermissions: [String]
    ) -> Bool {
        !emulatedPermissions.isDisjoint(with: requestedPermissions)
    }

    private func installExtensionPageCompatibility(
        in resourceURL: URL,
        manifest: [String: Any]
    ) throws -> Bool {
        var installed = false
        let sandboxPages = Self.sandboxPagePaths(in: manifest)
        guard let enumerator = fileManager.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else { return false }

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
                    in: resourceURL
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
        in manifest: inout [String: Any]
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
        marksBackground: Bool = false
    ) throws -> Bool {
        let pageURL = try validatedResourceURL(
            for: relativePath,
            in: resourceURL
        )
        var source = try String(contentsOf: pageURL, encoding: .utf8)
        let compatibilityTag =
            #"<script src="/crest-webextension-compatibility.js"></script>"#
        let relativeCompatibilityTag =
            #"<script src="crest-webextension-compatibility.js"></script>"#
        let markerTag =
            #"<script src="/crest-webextension-background-marker.js"></script>"#
        let relativeMarkerTag =
            #"<script src="crest-webextension-background-marker.js"></script>"#
        var tags: [String] = []
        if marksBackground,
            !source.contains(markerTag),
            !source.contains(relativeMarkerTag)
        {
            tags.append(markerTag)
        }
        if !source.contains(compatibilityTag),
            !source.contains(relativeCompatibilityTag)
        {
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
            throw BrowserChromeWebStoreCompatibilityPackageError
                .unsafeBackgroundPath
        }
        let candidate = resourceURL.appending(path: relativePath)
            .standardizedFileURL
        guard
            candidate.path.hasPrefix(
                resourceURL.standardizedFileURL.path + "/"
            ), fileManager.fileExists(atPath: candidate.path)
        else {
            throw BrowserChromeWebStoreCompatibilityPackageError
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
            throw BrowserChromeWebStoreCompatibilityPackageError
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
                const setting = Object.freeze({
                    onChange: noopEvent,
                    get(...args) {
                        return callbackOrPromise(args, {
                            value: false,
                            levelOfControl: "not_controllable"
                        });
                    },
                    set(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "This browser setting is not controllable in Crest."
                        );
                    },
                    clear(...args) {
                        return rejectCallbackOrPromise(
                            args,
                            "This browser setting is not controllable in Crest."
                        );
                    }
                });
                const overlay = (nativeValue, fallback) => new Proxy(
                    nativeValue ?? {},
                    {
                        get(target, property) {
                            const value = Reflect.get(target, property, target);
                            if (value === undefined) return fallback[property];
                            return typeof value === "function"
                                ? value.bind(target)
                                : value;
                        },
                        has(target, property) {
                            return property in target || property in fallback;
                        }
                    }
                );
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
                    passwordSavingEnabled: setting,
                    autofillCreditCardEnabled: setting,
                    autofillAddressEnabled: setting
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
                const createMessageBootstrap = (nativeRoot) => {
                    const nativeRuntime = nativeRoot?.runtime;
                    const nativeEvent = nativeRuntime?.onMessage;
                    if (
                        !nativeRuntime
                        || typeof nativeEvent?.addListener !== "function"
                        || typeof nativeEvent?.removeListener !== "function"
                    ) {
                        return undefined;
                    }

                    const nativeAdd = nativeEvent.addListener.bind(nativeEvent);
                    const nativeRemove =
                        nativeEvent.removeListener.bind(nativeEvent);
                    const nativeHas = typeof nativeEvent.hasListener === "function"
                        ? nativeEvent.hasListener.bind(nativeEvent)
                        : () => false;
                    const listeners = new Map();
                    const handledMessages = new Set();
                    let extensionPageMessaging;
                    let contentScriptMessaging;
                    let completeInitialization;
                    let isComplete = false;
                    const initialization = new Promise((resolve) => {
                        completeInitialization = resolve;
                    });
                    const keepsMessageChannelOpen = (result) => (
                        result === true
                        || (result !== null
                            && (typeof result === "object"
                                || typeof result === "function")
                            && typeof result.then === "function")
                    );
                    const isThenable = (value) => (
                        value !== null
                        && (typeof value === "object"
                            || typeof value === "function")
                        && typeof value.then === "function"
                    );
                    const normalizedSelfMessage = (args) => {
                        const values = Array.from(args);
                        const callback = typeof values.at(-1) === "function"
                            ? values.pop()
                            : undefined;
                        if (values.length === 0) return undefined;

                        let targetExtensionID;
                        let message;
                        if (values.length >= 3) {
                            targetExtensionID = values[0];
                            message = values[1];
                        } else if (
                            values.length === 2
                            && typeof values[0] === "string"
                        ) {
                            const possibleOptions = values[1];
                            const optionKeys = possibleOptions
                                && typeof possibleOptions === "object"
                                ? Object.keys(possibleOptions)
                                : [];
                            const isOptions = possibleOptions == null
                                || optionKeys.every(
                                    (key) => key === "includeTlsChannelId"
                                );
                            if (isOptions) {
                                message = values[0];
                            } else {
                                targetExtensionID = values[0];
                                message = values[1];
                            }
                        } else {
                            message = values[0];
                        }
                        if (
                            targetExtensionID !== undefined
                            && targetExtensionID !== extensionID
                        ) {
                            return undefined;
                        }
                        return { message, callback };
                    };
                    const isExtensionPage = () => {
                        if (typeof location === "undefined") return false;
                        try {
                            const base = new URL(extensionBaseURL);
                            return location.protocol === base.protocol
                                && location.host === base.host;
                        } catch {
                            return false;
                        }
                    };
                    const markHandled = (message) => {
                        handledMessages.add(message);
                    };
                    const wasHandled = (message) =>
                        handledMessages.has(message);
                    const wrappedListener = (listener) => {
                        let wrapped = listeners.get(listener);
                        if (wrapped) return wrapped;

                        wrapped = (message, sender, sendResponse) => {
                            let didRespond = false;
                            const trackedSendResponse = (...args) => {
                                didRespond = true;
                                markHandled(message);
                                return sendResponse(...args);
                            };
                            const result = listener(
                                message,
                                sender,
                                trackedSendResponse
                            );
                            if (
                                didRespond
                                || keepsMessageChannelOpen(result)
                            ) {
                                markHandled(message);
                            }
                            return result;
                        };
                        listeners.set(listener, wrapped);
                        return wrapped;
                    };
                    const eventCompatibility = new Proxy(nativeEvent, {
                        get(target, property) {
                            if (property === "addListener") {
                                return (listener) => {
                                    nativeAdd(wrappedListener(listener));
                                    extensionPageMessaging
                                        ?.retryPendingRequests();
                                    contentScriptMessaging
                                        ?.retryPendingRequests();
                                };
                            }
                            if (property === "removeListener") {
                                return (listener) => {
                                    const wrapped = listeners.get(listener);
                                    nativeRemove(wrapped ?? listener);
                                    if (wrapped) listeners.delete(listener);
                                };
                            }
                            if (property === "hasListener") {
                                return (listener) => nativeHas(
                                    listeners.get(listener) ?? listener
                                );
                            }
                            return Reflect.get(target, property, target);
                        }
                    });
                    const replayAfterInitialization = (
                        message,
                        sender,
                        sendResponse
                    ) => {
                        initialization.then(() => {
                            if (wasHandled(message)) return;

                            for (const listener of listeners.values()) {
                                const result = listener(
                                    message,
                                    sender,
                                    sendResponse
                                );
                                if (
                                    wasHandled(message)
                                    || keepsMessageChannelOpen(result)
                                ) {
                                    return;
                                }
                            }
                        });
                        return true;
                    };
                    nativeAdd(replayAfterInitialization);

                    const finish = () => {
                        if (isComplete) return;
                        isComplete = true;
                        nativeRemove(replayAfterInitialization);
                        completeInitialization();
                        queueMicrotask(() => handledMessages.clear());
                    };
                    const previousBackgroundCompletion = globalThis
                        .__crestCompleteWebExtensionBackgroundBootstrap;
                    const completeBackgroundBootstrap = () => {
                        previousBackgroundCompletion?.();
                        finish();
                    };
                    try {
                        Object.defineProperty(
                            globalThis,
                            "__crestCompleteWebExtensionBackgroundBootstrap",
                            {
                                value: completeBackgroundBootstrap,
                                configurable: true
                            }
                        );
                    } catch {
                        globalThis.__crestCompleteWebExtensionBackgroundBootstrap =
                            completeBackgroundBootstrap;
                    }
                    const invokePendingRequest = (request) => {
                        if (request.isSettled || request.isClaimed) return;

                        for (const listener of listeners.keys()) {
                            if (request.attemptedListeners.has(listener)) {
                                continue;
                            }
                            request.attemptedListeners.add(listener);
                            let didRespond = false;
                            const sendResponse = (response) => {
                                didRespond = true;
                                request.respond(response);
                                return true;
                            };
                            let result;
                            try {
                                result = listener(
                                    request.message,
                                    request.sender,
                                    sendResponse
                                );
                            } catch {
                                continue;
                            }
                            if (didRespond) return;
                            if (result === true) {
                                request.isClaimed = true;
                                return;
                            }
                            if (isThenable(result)) {
                                request.isClaimed = true;
                                Promise.resolve(result).then(
                                    (response) => request.respond(response),
                                    (error) => request.respond(
                                        undefined,
                                        String(error)
                                    )
                                );
                                return;
                            }
                        }
                    };
                    extensionPageMessaging = (() => {
                        if (typeof BroadcastChannel !== "function") {
                            return undefined;
                        }

                        let channel;
                        try {
                            channel = new BroadcastChannel(
                                `crest-webextension-messages:${extensionID}`
                            );
                        } catch {
                            return undefined;
                        }

                        const contextToken = globalThis.crypto
                            ?.randomUUID?.()
                            ?? `${Date.now()}-${Math.random()}`;
                        const pendingIncoming = new Map();
                        const pendingOutgoing = new Map();
                        const responseTimeoutMilliseconds = 30_000;
                        let requestSequence = 0;
                        const receiveRequest = (payload) => {
                            if (
                                payload.senderToken === contextToken
                                || pendingIncoming.has(payload.requestID)
                            ) {
                                return;
                            }
                            const request = {
                                requestID: payload.requestID,
                                message: payload.message,
                                sender: payload.sender ?? {
                                    id: extensionID,
                                    url: "",
                                    origin: extensionBaseURL
                                },
                                attemptedListeners: new Set(),
                                isClaimed: false,
                                isSettled: false
                            };
                            request.respond = (response, error) => {
                                if (request.isSettled) return;
                                request.isSettled = true;
                                clearTimeout(request.timeout);
                                pendingIncoming.delete(request.requestID);
                                channel.postMessage({
                                    kind: "response",
                                    requestID: request.requestID,
                                    senderToken: contextToken,
                                    response,
                                    error
                                });
                            };
                            request.timeout = setTimeout(() => {
                                request.isSettled = true;
                                pendingIncoming.delete(request.requestID);
                            }, responseTimeoutMilliseconds);
                            pendingIncoming.set(request.requestID, request);
                            invokePendingRequest(request);
                        };
                        const receiveResponse = (payload) => {
                            const pending = pendingOutgoing.get(
                                payload.requestID
                            );
                            if (!pending) return;

                            pendingOutgoing.delete(payload.requestID);
                            clearTimeout(pending.timeout);
                            if (pending.callback) {
                                queueMicrotask(() => pending.callback(
                                    payload.response
                                ));
                            } else if (payload.error) {
                                pending.reject(new Error(payload.error));
                            } else {
                                pending.resolve(payload.response);
                            }
                        };
                        channel.addEventListener("message", (event) => {
                            const payload = event.data;
                            if (
                                !payload
                                || typeof payload !== "object"
                                || payload.senderToken === contextToken
                            ) {
                                return;
                            }
                            if (payload.kind === "request") {
                                receiveRequest(payload);
                            } else if (payload.kind === "response") {
                                receiveResponse(payload);
                            }
                        });
                        const sendMessage = (...args) => {
                            const normalized = normalizedSelfMessage(args);
                            if (!normalized) {
                                return { handled: false };
                            }

                            const requestID =
                                `${contextToken}:${++requestSequence}`;
                            const sender = {
                                id: extensionID,
                                url: typeof location === "undefined"
                                    ? ""
                                    : location.href,
                                origin: extensionBaseURL
                            };
                            if (normalized.callback) {
                                const timeout = setTimeout(() => {
                                    pendingOutgoing.delete(requestID);
                                    normalized.callback(undefined);
                                }, responseTimeoutMilliseconds);
                                pendingOutgoing.set(requestID, {
                                    callback: normalized.callback,
                                    timeout
                                });
                                channel.postMessage({
                                    kind: "request",
                                    requestID,
                                    senderToken: contextToken,
                                    message: normalized.message,
                                    sender
                                });
                                return { handled: true, value: undefined };
                            }
                            const value = new Promise((resolve, reject) => {
                                const timeout = setTimeout(() => {
                                    pendingOutgoing.delete(requestID);
                                    reject(new Error(
                                        "No extension page handled the message."
                                    ));
                                }, responseTimeoutMilliseconds);
                                pendingOutgoing.set(requestID, {
                                    resolve,
                                    reject,
                                    timeout
                                });
                                channel.postMessage({
                                    kind: "request",
                                    requestID,
                                    senderToken: contextToken,
                                    message: normalized.message,
                                    sender
                                });
                            });
                            return { handled: true, value };
                        };
                        return {
                            canSend: isExtensionPage,
                            sendMessage,
                            retryPendingRequests() {
                                for (const request of pendingIncoming.values()) {
                                    invokePendingRequest(request);
                                }
                            }
                        };
                    })();
                    contentScriptMessaging = (() => {
                        const portName =
                            "crest-webextension-runtime-messages-v1";
                        const responseTimeoutMilliseconds = 30_000;
                        const onConnect = nativeRuntime.onConnect;
                        const nativeConnect = nativeRuntime.connect;

                        if (
                            globalThis.__crestIsWebExtensionBackground === true
                        ) {
                            if (typeof onConnect?.addListener !== "function") {
                                return undefined;
                            }

                            const pendingIncoming = new Set();
                            onConnect.addListener((port) => {
                                if (
                                    port?.name !== portName
                                    || typeof port.onMessage?.addListener
                                        !== "function"
                                    || typeof port.postMessage !== "function"
                                ) {
                                    return;
                                }

                                const requests = new Set();
                                const settleRequest = (request) => {
                                    request.isSettled = true;
                                    clearTimeout(request.timeout);
                                    requests.delete(request);
                                    pendingIncoming.delete(request);
                                };
                                port.onMessage.addListener((payload) => {
                                    if (
                                        !payload
                                        || payload.kind !== "request"
                                        || typeof payload.requestID !== "string"
                                    ) {
                                        return;
                                    }

                                    const request = {
                                        requestID: payload.requestID,
                                        message: payload.message,
                                        sender: port.sender ?? {
                                            id: extensionID,
                                            url: "",
                                            origin: extensionBaseURL
                                        },
                                        attemptedListeners: new Set(),
                                        isClaimed: false,
                                        isSettled: false
                                    };
                                    request.respond = (response, error) => {
                                        if (request.isSettled) return;
                                        settleRequest(request);
                                        try {
                                            port.postMessage({
                                                kind: "response",
                                                requestID: request.requestID,
                                                response,
                                                error
                                            });
                                        } catch {}
                                    };
                                    request.timeout = setTimeout(
                                        () => settleRequest(request),
                                        responseTimeoutMilliseconds
                                    );
                                    requests.add(request);
                                    pendingIncoming.add(request);
                                    invokePendingRequest(request);
                                });
                                if (
                                    typeof port.onDisconnect?.addListener
                                    === "function"
                                ) {
                                    port.onDisconnect.addListener(() => {
                                        for (const request of requests) {
                                            settleRequest(request);
                                        }
                                    });
                                }
                            });

                            return {
                                canSend: () => false,
                                sendMessage: () => ({ handled: false }),
                                retryPendingRequests() {
                                    for (const request of pendingIncoming) {
                                        invokePendingRequest(request);
                                    }
                                }
                            };
                        }

                        if (
                            isExtensionPage()
                            || typeof nativeConnect !== "function"
                        ) {
                            return undefined;
                        }

                        let port;
                        let requestSequence = 0;
                        const pendingOutgoing = new Map();
                        const settlePending = (requestID, payload = {}) => {
                            const pending = pendingOutgoing.get(requestID);
                            if (!pending) return;

                            pendingOutgoing.delete(requestID);
                            clearTimeout(pending.timeout);
                            if (pending.callback) {
                                queueMicrotask(() => pending.callback(
                                    payload.response
                                ));
                            } else if (payload.error) {
                                pending.reject(new Error(payload.error));
                            } else {
                                pending.resolve(payload.response);
                            }
                        };
                        const disconnect = () => {
                            port = undefined;
                            for (const requestID of pendingOutgoing.keys()) {
                                settlePending(requestID, {
                                    error: "The extension background disconnected."
                                });
                            }
                        };
                        const connectedPort = () => {
                            if (port) return port;

                            let nextPort;
                            try {
                                nextPort = nativeConnect.call(nativeRuntime, {
                                    name: portName
                                });
                            } catch {
                                return undefined;
                            }
                            if (
                                !nextPort
                                || typeof nextPort.postMessage !== "function"
                                || typeof nextPort.onMessage?.addListener
                                    !== "function"
                            ) {
                                return undefined;
                            }
                            port = nextPort;
                            nextPort.onMessage.addListener((payload) => {
                                if (
                                    payload?.kind !== "response"
                                    || typeof payload.requestID !== "string"
                                ) {
                                    return;
                                }
                                settlePending(payload.requestID, payload);
                            });
                            if (
                                typeof nextPort.onDisconnect?.addListener
                                === "function"
                            ) {
                                nextPort.onDisconnect.addListener(disconnect);
                            }
                            return nextPort;
                        };
                        const sendMessage = (...args) => {
                            const normalized = normalizedSelfMessage(args);
                            if (!normalized) return { handled: false };

                            const activePort = connectedPort();
                            if (!activePort) return { handled: false };

                            const requestID =
                                `content:${Date.now()}:${++requestSequence}`;
                            let value;
                            let pending;
                            if (normalized.callback) {
                                pending = { callback: normalized.callback };
                            } else {
                                value = new Promise((resolve, reject) => {
                                    pending = { resolve, reject };
                                });
                            }
                            pending.timeout = setTimeout(() => {
                                settlePending(requestID, {
                                    error: "No extension background handled the message."
                                });
                            }, responseTimeoutMilliseconds);
                            pendingOutgoing.set(requestID, pending);
                            try {
                                activePort.postMessage({
                                    kind: "request",
                                    requestID,
                                    message: normalized.message
                                });
                            } catch {
                                pendingOutgoing.delete(requestID);
                                clearTimeout(pending.timeout);
                                return { handled: false };
                            }
                            return { handled: true, value };
                        };
                        return {
                            canSend: () => true,
                            sendMessage,
                            retryPendingRequests() {}
                        };
                    })();
                    return {
                        nativeRoot,
                        onMessage: eventCompatibility,
                        extensionPageMessaging,
                        contentScriptMessaging
                    };
                };
                const messageBootstraps = new Map();
                const messageBootstrapFor = (nativeRoot) => {
                    if (!nativeRoot) return undefined;
                    let bootstrap = messageBootstraps.get(nativeRoot);
                    if (bootstrap) return bootstrap;

                    bootstrap = createMessageBootstrap(nativeRoot);
                    if (bootstrap) messageBootstraps.set(nativeRoot, bootstrap);
                    return bootstrap;
                };
                messageBootstrapFor(primaryRoot);
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
                const readNativeManifest = (nativeRuntime, args) => {
                    const getManifest = nativeRuntime?.getManifest;
                    if (typeof getManifest !== "function") return undefined;
                    try {
                        const manifest = getManifest.apply(nativeRuntime, args);
                        return manifest && typeof manifest === "object"
                            ? manifest
                            : undefined;
                    } catch {
                        return undefined;
                    }
                };
                const manifestCompatibility = (nativeRuntime, args) => (
                    readNativeManifest(nativeRuntime, args)
                    ?? readNativeManifest(nativeChrome?.runtime, args)
                    ?? readNativeManifest(nativeBrowser?.runtime, args)
                    ?? declaredManifest
                );
                const compatibleRuntimeFor = (nativeRoot) => {
                    const nativeRuntime = nativeRoot?.runtime;
                    if (!nativeRuntime) return runtime;
                    const messageBootstrap = messageBootstrapFor(nativeRoot);

                    return new Proxy(nativeRuntime, {
                        get(target, property) {
                            if (
                                property === "onMessage"
                                && messageBootstrap?.nativeRoot === nativeRoot
                            ) {
                                return messageBootstrap.onMessage;
                            }
                            if (property === "getManifest") {
                                return (...args) => manifestCompatibility(
                                    target,
                                    args
                                );
                            }
                            if (property === "sendMessage") {
                                const nativeSendMessage = Reflect.get(
                                    target,
                                    property,
                                    target
                                );
                                const messageRouting = [
                                    messageBootstrap?.extensionPageMessaging,
                                    messageBootstrap?.contentScriptMessaging
                                ].find((candidate) => candidate?.canSend());
                                if (messageRouting) {
                                    return (...args) => {
                                        const attempt = messageRouting
                                            .sendMessage(...args);
                                        if (attempt.handled) {
                                            return attempt.value;
                                        }
                                        if (
                                            typeof nativeSendMessage
                                            !== "function"
                                        ) {
                                            return runtime[property];
                                        }
                                        return nativeSendMessage.apply(
                                            target,
                                            args
                                        );
                                    };
                                }
                                if (typeof nativeSendMessage !== "function") {
                                    return runtime[property];
                                }
                                return (...args) => nativeSendMessage.apply(
                                    target,
                                    args
                                );
                            }
                            if (property === "id") {
                                const nativeID = Reflect.get(
                                    target,
                                    property,
                                    target
                                );
                                return typeof nativeID === "string"
                                    && nativeID.length > 0
                                    ? nativeID
                                    : extensionID;
                            }
                            if (property === "getURL") {
                                return (path = "") => {
                                    const nativeGetURL = Reflect.get(
                                        target,
                                        property,
                                        target
                                    );
                                    if (typeof nativeGetURL === "function") {
                                        try {
                                            const nativeURL = nativeGetURL.call(
                                                target,
                                                path
                                            );
                                            if (
                                                typeof nativeURL === "string"
                                                && nativeURL.length > 0
                                            ) {
                                                return new URL(nativeURL).href;
                                            }
                                        } catch {}
                                    }
                                    return fallbackResourceURL(path);
                                };
                            }
                            const value = Reflect.get(target, property, target);
                            if (value === undefined) return runtime[property];
                            return typeof value === "function"
                                ? value.bind(target)
                                : value;
                        }
                    });
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
                const compatibilityFor = (nativeRoot) => {
                    installFallbacks(nativeRoot, fallbacksFor(nativeRoot));
                    return ({
                    action: overlay(nativeRoot.action, action),
                    browserAction: overlay(nativeRoot.browserAction, action),
                    permissions: overlay(nativeRoot.permissions, permissions),
                    privacy: overlay(nativeRoot.privacy, {
                        services: overlay(
                            nativeRoot.privacy?.services,
                            privacyServices
                        )
                    }),
                    storage: overlay(nativeRoot.storage, {
                        managed: overlay(
                            nativeRoot.storage?.managed,
                            storageManaged
                        )
                    }),
                    notifications: overlay(
                        nativeRoot.notifications,
                        notifications
                    ),
                    offscreen: overlay(nativeRoot.offscreen, offscreen),
                    management: overlay(nativeRoot.management, management),
                    downloads: overlay(nativeRoot.downloads, downloads),
                    idle: overlay(nativeRoot.idle, idle),
                    webRequest: overlay(nativeRoot.webRequest, webRequest),
                    webNavigation: overlay(
                        nativeRoot.webNavigation,
                        webNavigation
                    ),
                    runtime: overlay(nativeRoot.runtime, runtime)
                    });
                };
                const installCompatibility = (name, nativeRoot) => {
                    if (!nativeRoot) return;

                    const fallback = compatibilityFor(nativeRoot);
                    const compatibleRuntime = compatibleRuntimeFor(nativeRoot);
                    const compatibleRoot = new Proxy(nativeRoot, {
                        get(target, property) {
                            if (property === "runtime") {
                                return compatibleRuntime;
                            }
                            const value = Reflect.get(target, property, target);
                            return value === undefined
                                ? fallback[property]
                                : value;
                        },
                        has(target, property) {
                            return property in target || property in fallback;
                        }
                    });
                    try {
                        Object.defineProperty(globalThis, name, {
                            value: compatibleRoot,
                            configurable: true
                        });
                    } catch {
                        try { globalThis[name] = compatibleRoot; } catch {}
                    }
                    return compatibleRoot;
                };
                const chromeCompatibility = installCompatibility(
                    "chrome",
                    nativeChrome ?? nativeBrowser
                );
                const browserCompatibility = installCompatibility(
                    "browser",
                    nativeBrowser ?? nativeChrome
                );
            })();
            """
    }

}
