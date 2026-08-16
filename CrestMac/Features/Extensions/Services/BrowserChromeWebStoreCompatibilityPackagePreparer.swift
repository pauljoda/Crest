import Foundation

struct BrowserChromeWebStoreCompatibilityPackagePreparer {
    private static let compatibilityScriptName =
        "crest-webextension-compatibility.js"
    private static let backgroundPageName =
        "crest-webextension-background.html"
    private static let backgroundBootstrapName =
        "crest-webextension-background-bootstrap.js"
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
        requestedPermissions: [String]
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
                requestedPermissions: requestedPermissions
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
        requestedPermissions: [String]
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
            manifest: manifest
        )
        try compatibilityScript.write(
            to: resourceURL.appending(path: Self.compatibilityScriptName),
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
                try (compatibilityScript + "\n\n" + originalWorker).write(
                    to: workerURL,
                    atomically: true,
                    encoding: .utf8
                )
            }
            return true
        }

        if var scripts = background["scripts"] as? [String] {
            if !scripts.contains(Self.compatibilityScriptName) {
                scripts.insert(Self.compatibilityScriptName, at: 0)
                background["scripts"] = scripts
                manifest["background"] = background
            }
            return true
        }

        if let page = background["page"] as? String {
            return try injectCompatibilityScript(
                into: page,
                in: resourceURL
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
        for path in Self.extensionPagePaths(in: manifest) {
            installed =
                try injectCompatibilityScript(
                    into: path,
                    in: resourceURL
                ) || installed
        }
        return installed
    }

    private static func extensionPagePaths(
        in manifest: [String: Any]
    ) -> Set<String> {
        var paths = Set<String>()
        for key in ["action", "browser_action", "page_action"] {
            if let section = manifest[key] as? [String: Any],
                let path = section["default_popup"] as? String
            {
                paths.insert(path)
            }
        }
        if let path = manifest["options_page"] as? String {
            paths.insert(path)
        }
        if let section = manifest["options_ui"] as? [String: Any],
            let path = section["page"] as? String
        {
            paths.insert(path)
        }
        if let section = manifest["side_panel"] as? [String: Any],
            let path = section["default_path"] as? String
        {
            paths.insert(path)
        }
        if let path = manifest["devtools_page"] as? String {
            paths.insert(path)
        }
        if let overrides = manifest["chrome_url_overrides"]
            as? [String: String]
        {
            paths.formUnion(overrides.values)
        }
        if let sandbox = manifest["sandbox"] as? [String: Any],
            let pages = sandbox["pages"] as? [String]
        {
            paths.formUnion(pages)
        }
        return paths
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
        in resourceURL: URL
    ) throws -> Bool {
        let pageURL = try validatedResourceURL(
            for: relativePath,
            in: resourceURL
        )
        var source = try String(contentsOf: pageURL, encoding: .utf8)
        let tag =
            #"<script src="/crest-webextension-compatibility.js"></script>"#
        guard !source.contains(tag) else { return false }

        if let headStart = source.range(
            of: "<head",
            options: [.caseInsensitive]
        ),
            let headEnd = source.range(
                of: ">",
                range: headStart.lowerBound..<source.endIndex
            )
        {
            source.insert(contentsOf: "\n\(tag)", at: headEnd.upperBound)
        } else {
            source.insert(contentsOf: tag + "\n", at: source.startIndex)
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
        manifest: [String: Any]
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
                            return value === undefined ? fallback[property] : value;
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
                    const handledMessages = new WeakSet();
                    let completeInitialization;
                    let isComplete = false;
                    const initialization = new Promise((resolve) => {
                        completeInitialization = resolve;
                    });
                    const markHandled = (message) => {
                        if (
                            (typeof message === "object" && message !== null)
                            || typeof message === "function"
                        ) {
                            handledMessages.add(message);
                        }
                    };
                    const wasHandled = (message) => (
                        ((typeof message === "object" && message !== null)
                            || typeof message === "function")
                        && handledMessages.has(message)
                    );
                    const wrappedListener = (listener) => {
                        let wrapped = listeners.get(listener);
                        if (wrapped) return wrapped;

                        wrapped = (message, sender, sendResponse) => {
                            const result = listener(
                                message,
                                sender,
                                sendResponse
                            );
                            if (result !== false) markHandled(message);
                            return result;
                        };
                        listeners.set(listener, wrapped);
                        return wrapped;
                    };
                    const eventCompatibility = new Proxy(nativeEvent, {
                        get(target, property) {
                            if (property === "addListener") {
                                return (listener) => nativeAdd(
                                    wrappedListener(listener)
                                );
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
                                if (result !== false) return;
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
                    };
                    try {
                        Object.defineProperty(
                            globalThis,
                            "__crestCompleteWebExtensionBackgroundBootstrap",
                            { value: finish, configurable: true }
                        );
                    } catch {
                        globalThis.__crestCompleteWebExtensionBackgroundBootstrap =
                            finish;
                    }
                    return {
                        nativeRoot,
                        onMessage: eventCompatibility
                    };
                };
                const messageBootstrap = createMessageBootstrap(primaryRoot);
                const runtime = {
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
                            const value = Reflect.get(target, property, target);
                            return value === undefined ? runtime[property] : value;
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
