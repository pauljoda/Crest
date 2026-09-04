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

        // Keep `_execute_sidebar_action` as an ordinary WebKit command. Crest
        // handles its native invocation before commands.onCommand is dispatched.

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
    private static let preparationLock = NSLock()
    private static let preparedDigestFilename = ".crest-prepared-digest"
    private static let scopedCompatibilityAPIName =
        "__crestWebExtensionScopedAPI"
    private static let legacyBackgroundPreludePattern =
        #"(?s)\A// Crest's WKWebExtension host currently has no notifications API\.\s*.*?Object\.defineProperty\(globalThis, \"chrome\", \{\s*value: crestChromeCompatibility,\s*configurable: true\s*\}\);\s*\}\s*"#

    private let fileManager: FileManager
    private let expandArchive: (URL, URL) throws -> Void
    /// Whether the generated runtime forwards the extension's own
    /// `console.warn`/`error`/`info` output to Crest's diagnostics channel.
    ///
    /// Off by default. Console forwarding is how a *hang* becomes readable —
    /// nothing throws, and the extension's own log lines are the only trace —
    /// but it wraps three functions every extension page calls, so a shipping
    /// build does not pay for it. Flipping this changes the runtime's contents
    /// and therefore its content-addressed filename, which is exactly the
    /// invalidation the prepared-package digest already expects.
    private let enablesConsoleCapture: Bool

    init(
        fileManager: FileManager = .default,
        expandArchive: @escaping (URL, URL) throws -> Void = Self.expand,
        enablesConsoleCapture: Bool = false
    ) {
        self.fileManager = fileManager
        self.expandArchive = expandArchive
        self.enablesConsoleCapture = enablesConsoleCapture
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

        // WKWebExtension persists service workers, dynamic content scripts,
        // permissions, and storage against the extension's resource base URL.
        // A fresh temporary URL on every restore makes an unchanged package
        // look like an update and can make WebKit remove those stores while the
        // restored context is already starting. Keep the URL stable for the
        // lifetime of the stored package and publish changed prepared contents
        // back to that same URL.
        let rootURL = stablePreparedRootURL(
            for: storedResourceURL,
            runtimeIdentity: runtimeIdentity
        )
        let resourceURL = rootURL.appending(
            path: "resources",
            directoryHint: .isDirectory
        )
        let stagingRootURL = fileManager.temporaryDirectory.appending(
            path: "crest-restored-extension-compatibility-staging-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let stagingResourceURL = stagingRootURL.appending(
            path: "resources",
            directoryHint: .isDirectory
        )

        Self.preparationLock.lock()
        defer { Self.preparationLock.unlock() }
        do {
            try fileManager.createDirectory(
                at: stagingRootURL,
                withIntermediateDirectories: true
            )
            let resourceValues = try storedResourceURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            if resourceValues.isDirectory == true {
                try fileManager.copyItem(
                    at: storedResourceURL,
                    to: stagingResourceURL
                )
            } else if resourceValues.isRegularFile == true {
                try expandArchive(storedResourceURL, stagingResourceURL)
            } else {
                throw BrowserWebExtensionCompatibilityPackageError
                    .archiveExpansionFailed
            }
            let installed = try installCompatibilityLayer(
                in: stagingResourceURL,
                requestedPermissions: requestedPermissions,
                runtimeIdentity: runtimeIdentity
            )
            guard installed else {
                try? fileManager.removeItem(at: stagingRootURL)
                return nil
            }
            // WebKit's runtime summary omits permissions for APIs it does not
            // implement. Those are precisely the declarations Crest's broker
            // needs (for example `idle`), so recover them from the prepared
            // package instead of treating the lossy summary as authoritative.
            let preparedManifest = try Self.packageManifest(
                in: stagingResourceURL
            )
            let manifestPermissions = preparedManifest["permissions"] as? [String] ?? []
            let effectiveRequestedPermissions = Array(
                Set(requestedPermissions).union(manifestPermissions)
            )
            let preparedDigest = try preparedContentDigest(
                at: stagingResourceURL
            )
            let existingDigest = try? String(
                contentsOf: rootURL.appending(
                    path: Self.preparedDigestFilename
                ),
                encoding: .utf8
            )
            if existingDigest == preparedDigest,
                fileManager.fileExists(atPath: resourceURL.path)
            {
                try? fileManager.removeItem(at: stagingRootURL)
            } else {
                try retainPublishedCompatibilityResources(
                    from: resourceURL,
                    in: stagingResourceURL
                )
                try preparedDigest.write(
                    to: stagingRootURL.appending(
                        path: Self.preparedDigestFilename
                    ),
                    atomically: true,
                    encoding: .utf8
                )
                try publishPreparedRoot(
                    stagingRootURL,
                    at: rootURL
                )
            }
            return BrowserWebExtensionPreparedPackage(
                resourceURL: resourceURL,
                rootURL: rootURL,
                fileManager: fileManager,
                removesRootOnDeinit: false,
                internalGrantedPermissions: Self.internalGrantedPermissions(
                    requestedPermissions: effectiveRequestedPermissions
                ),
                capabilityBrokerGrantedPermissions:
                    Self.capabilityBrokerGrantedPermissions(
                        requestedPermissions: effectiveRequestedPermissions
                    ).union(
                        BrowserExtensionAPICompatibilityMatrix.capabilityBrokerGrantedCapabilities(
                            manifest: preparedManifest)),
                allowsInternalCapabilityBroker: true
            )
        } catch {
            try? fileManager.removeItem(at: stagingRootURL)
            throw error
        }
    }

    private func retainPublishedCompatibilityResources(
        from publishedResourceURL: URL,
        in stagingResourceURL: URL
    ) throws {
        guard fileManager.fileExists(atPath: publishedResourceURL.path)
        else { return }

        let publishedResources = try fileManager.contentsOfDirectory(
            at: publishedResourceURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        // WebKit can retain a service-worker registration after Crest prepares
        // a newer compatibility generation. Generated resources are immutable
        // and content-addressed, so carrying them forward keeps both the old
        // registration and the newly published manifest resolvable.
        for publishedResource in publishedResources
        where publishedResource.lastPathComponent.hasPrefix(
            "crest-webextension-"
        ) {
            let values = try publishedResource.resourceValues(
                forKeys: [.isRegularFileKey]
            )
            guard values.isRegularFile == true else { continue }
            let stagedResource = stagingResourceURL.appending(
                path: publishedResource.lastPathComponent
            )
            guard !fileManager.fileExists(atPath: stagedResource.path)
            else { continue }
            try fileManager.copyItem(
                at: publishedResource,
                to: stagedResource
            )
        }
    }

    private func stablePreparedRootURL(
        for storedResourceURL: URL,
        runtimeIdentity: BrowserExtensionRuntimeIdentity
    ) -> URL {
        let sourceIdentity = [
            storedResourceURL.resolvingSymlinksInPath()
                .standardizedFileURL.path,
            runtimeIdentity.extensionID,
            runtimeIdentity.uniqueIdentifier,
            runtimeIdentity.baseURL.absoluteString,
            runtimeIdentity.referenceEnvironment.rawValue,
        ].joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(sourceIdentity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return fileManager.temporaryDirectory
            .appending(
                path: "crest-restored-extension-compatibility",
                directoryHint: .isDirectory
            )
            .appending(path: digest, directoryHint: .isDirectory)
    }

    private func preparedContentDigest(at resourceURL: URL) throws -> String {
        var hasher = SHA256()
        let relativePaths = try fileManager.subpathsOfDirectory(
            atPath: resourceURL.path
        ).sorted()
        for relativePath in relativePaths {
            let fileURL = resourceURL.appending(path: relativePath)
            let values = try fileURL.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            if values.isSymbolicLink == true {
                hasher.update(data: Data("link".utf8))
                let destination = try fileManager.destinationOfSymbolicLink(
                    atPath: fileURL.path
                )
                hasher.update(data: Data(destination.utf8))
            } else if values.isDirectory == true {
                hasher.update(data: Data("directory".utf8))
            } else if values.isRegularFile == true {
                hasher.update(data: Data("file".utf8))
                hasher.update(data: try Data(contentsOf: fileURL))
            }
            hasher.update(data: Data([0]))
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func publishPreparedRoot(
        _ stagingRootURL: URL,
        at rootURL: URL
    ) throws {
        try fileManager.createDirectory(
            at: rootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.fileExists(atPath: rootURL.path) else {
            try fileManager.moveItem(at: stagingRootURL, to: rootURL)
            return
        }

        let backupRootURL = rootURL.deletingLastPathComponent().appending(
            path: ".crest-compatibility-backup-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        try fileManager.moveItem(at: rootURL, to: backupRootURL)
        do {
            try fileManager.moveItem(at: stagingRootURL, to: rootURL)
            try? fileManager.removeItem(at: backupRootURL)
        } catch {
            try? fileManager.moveItem(at: backupRootURL, to: rootURL)
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
        let failsWorkerWebSockets = Self.hasServiceWorkerBackground(
            manifest
        )
        let compatibilityScript = try Self.webExtensionCompatibilityScript(
            manifest: manifest,
            runtimeIdentity: runtimeIdentity,
            failsWorkerWebSockets: failsWorkerWebSockets,
            backgroundEnvironment: Self.preparedBackgroundEnvironment(
                manifest
            ),
            enablesConsoleCapture: enablesConsoleCapture
        )
        Self.normalizeManifestForWebKit(&manifest)
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

    private static func hasServiceWorkerBackground(
        _ manifest: [String: Any]
    ) -> Bool {
        let background = manifest["background"] as? [String: Any]
        return background?["service_worker"] is String
    }

    /// The environment the prepared background actually runs in.
    ///
    /// The authored manifest cannot answer this. A dual-environment package
    /// declares both `service_worker` and `scripts`; preparation keeps the
    /// document-ready scripts and drops the worker, so the compatibility
    /// runtime must not assume a worker owns durable events such as alarms.
    /// This mirrors the decision `installBackgroundCompatibility` makes.
    static func preparedBackgroundEnvironment(
        _ manifest: [String: Any]
    ) -> String {
        guard
            let background = manifest["background"] as? [String: Any],
            background["service_worker"] is String
        else { return "document" }
        if let scripts = background["scripts"] as? [String], !scripts.isEmpty {
            return "document"
        }
        return "worker"
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

            // Keep WebKit's native worker boundary for both worker types.
            // Hosting a module worker in a generated background document
            // makes that document visible to same-origin channels, but WebKit
            // does not route native runtime Ports or messages into it. Stable
            // per-Space origins already prevent one context from reusing
            // another context's service-worker registration.
            let backgroundBootstrapName = try installServiceWorkerBootstrap(
                in: resourceURL,
                serviceWorker: serviceWorker,
                isModule: background["type"] as? String == "module",
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
        isModule: Bool,
        compatibilityScriptName: String
    ) throws -> String {
        let compatibilitySpecifier = Self.javascriptStringLiteral(
            "./\(compatibilityScriptName)"
        )
        let workerSpecifier = Self.javascriptStringLiteral("./\(serviceWorker)")
        let backgroundBootstrap: String
        if isModule {
            backgroundBootstrap = """
                import \(compatibilitySpecifier);
                import \(workerSpecifier);
                """
        } else {
            let scopedAPIName = Self.javascriptStringLiteral(
                Self.scopedCompatibilityAPIName
            )
            backgroundBootstrap = """
                importScripts(\(compatibilitySpecifier));
                const { chrome, browser } = globalThis[\(scopedAPIName)];
                importScripts(\(workerSpecifier));
                """
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
        // Portable packages always receive the same browser contract. Runtime,
        // action, window, and worker APIs do not require manifest permissions,
        // so a permission gate can never describe whether preparation is needed.
        !BrowserExtensionAPICompatibilityMatrix.contracts.isEmpty
    }

    private static func normalizeManifestForWebKit(
        _ manifest: inout [String: Any]
    ) {
        BrowserWebExtensionManifestCompatibilityPolicy
            .normalizeCommandsForWebKit(in: &manifest)
        // The capability broker is a host grant, not an extension-authored
        // permission. WKWebExtensionContext can grant the native API before
        // load without rewriting the package manifest. Keeping the authored
        // manifest intact prevents extensions from enabling an optional
        // native-companion path solely because Crest needs private transport.
        normalizeDuplicateOptionalEntries(
            in: &manifest,
            requiredKey: "permissions",
            optionalKey: "optional_permissions"
        )
        normalizeDuplicateOptionalEntries(
            in: &manifest,
            requiredKey: "host_permissions",
            optionalKey: "optional_host_permissions"
        )
    }

    private static func normalizeDuplicateOptionalEntries(
        in manifest: inout [String: Any],
        requiredKey: String,
        optionalKey: String
    ) {
        guard
            let required = manifest[requiredKey] as? [String],
            var optional = manifest[optionalKey] as? [String]
        else { return }
        let requiredEntries = Set(required)
        optional.removeAll { requiredEntries.contains($0) }
        manifest[optionalKey] = optional
    }

    static func internalGrantedPermissions(
        requestedPermissions: [String]
    ) -> Set<String> {
        !requestedPermissions.contains(
            internalContextMenuTransportPermission
        )
            ? [internalContextMenuTransportPermission]
            : []
    }

    static func capabilityBrokerGrantedPermissions(
        requestedPermissions: [String]
    ) -> Set<String> {
        BrowserExtensionAPICompatibilityMatrix
            .capabilityBrokerGrantedPermissions(
                requestedPermissions: requestedPermissions
            )
    }

    private static func packageManifest(
        in resourceURL: URL
    ) throws -> [String: Any] {
        let manifestURL = resourceURL.appending(path: "manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest =
            try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        return manifest ?? [:]
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
        // Injection is the whole contract here. An extension's own markup is
        // vendor source: rewriting it — stripping attributes, normalizing
        // whitespace — patches a package Crest does not own, and any such
        // edit outlives the reason it was added.
        var source = try String(contentsOf: pageURL, encoding: .utf8)
        let compatibilityTag =
            #"<script src="/\#(compatibilityScriptName)"></script>"#
        guard !source.contains(compatibilityTag) else { return false }

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
                contentsOf: "\n\(compatibilityTag)",
                at: headEnd.upperBound
            )
        } else {
            source.insert(
                contentsOf: compatibilityTag + "\n",
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

    /// Re-indents a spliced script fragment so the generated runtime stays
    /// readable in Web Inspector, where an extension developer reads it.
    private static func indentedJavaScript(
        _ source: String,
        by spaces: Int
    ) -> String {
        let padding = String(repeating: " ", count: spaces)
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let indented = lines.map { $0.isEmpty ? "" : padding + $0 }
        return indented.joined(separator: "\n")
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
        runtimeIdentity: BrowserExtensionRuntimeIdentity,
        failsWorkerWebSockets: Bool,
        backgroundEnvironment: String,
        enablesConsoleCapture: Bool
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
        let compatibilityPermissionsData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix
                .compatibilityPermissionNames.sorted(),
            options: [.withoutEscapingSlashes]
        )
        guard
            let compatibilityPermissionsLiteral = String(
                data: compatibilityPermissionsData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let availableNamespacesData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.availableNamespaceNames,
            options: [.withoutEscapingSlashes]
        )
        guard
            let availableNamespacesLiteral = String(
                data: availableNamespacesData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let namespaceRoutesData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.namespaceRoutes,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let namespaceRoutesLiteral = String(
                data: namespaceRoutesData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let namespacePermissionsData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.namespacePermissions,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let namespacePermissionsLiteral = String(
                data: namespacePermissionsData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let namespaceManifestKeysData = try JSONSerialization.data(
            withJSONObject: BrowserExtensionAPICompatibilityMatrix.namespaceManifestKeys,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let namespaceManifestKeysLiteral = String(decoding: namespaceManifestKeysData, as: UTF8.self)
        let memberRoutesData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.memberRoutes,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let memberRoutesLiteral = String(
                data: memberRoutesData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let namespaceEventMembersData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.namespaceEventMembers,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let namespaceEventMembersLiteral = String(
                data: namespaceEventMembersData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let backgroundWorkerHiddenMembersData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix
                .backgroundWorkerHiddenMembers,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let backgroundWorkerHiddenMembersLiteral = String(
                data: backgroundWorkerHiddenMembersData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let namespaceProcessesData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.namespaceProcesses,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let namespaceProcessesLiteral = String(
                data: namespaceProcessesData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let memberProcessesData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.memberProcesses,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let memberProcessesLiteral = String(
                data: memberProcessesData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let emulatedSurfaceData = try JSONSerialization.data(
            withJSONObject:
                BrowserExtensionAPICompatibilityMatrix.emulatedSurface,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard
            let emulatedSurfaceLiteral = String(
                data: emulatedSurfaceData,
                encoding: .utf8
            )
        else {
            throw BrowserWebExtensionCompatibilityPackageError
                .invalidBackgroundManifest
        }
        let appendsChromiumNavigatorFamilyMarker =
            runtimeIdentity.referenceEnvironment == .chromium
        let workerWebSocketScript = Self.indentedJavaScript(
            BrowserExtensionWorkerWebSocketCompatibilityScript.source,
            by: 4
        )
        return """
            // Crest fills browser-neutral WebExtension surface gaps only when
            // WebKit does not expose a native implementation. Keep this runtime
            // capability-based: it must never branch on an extension identity.
            (() => {
                const nativeChrome = globalThis.chrome;
                const nativeBrowser = globalThis.browser;
                const primaryRoot = nativeChrome ?? nativeBrowser;
                if (!primaryRoot) return;
                const extensionBaseURL = \(javascriptStringLiteral(runtimeIdentity.baseURL.absoluteString));
                const appendsChromiumNavigatorFamilyMarker = \(appendsChromiumNavigatorFamilyMarker ? "true" : "false");
                const isBackgroundWorker =
                    typeof globalThis.document === "undefined";
                const isPrivilegedExtensionContext =
                    isBackgroundWorker
                    || String(globalThis.location?.href ?? "")
                        .startsWith(extensionBaseURL);
                const nativeRuntime = nativeBrowser?.runtime
                    ?? nativeChrome?.runtime;
                const nativeRuntimeWithMethod = (methodName) => {
                    // WebKit can refresh the live extension facade after this
                    // compatibility script starts (notably when an emulated
                    // permission makes native messaging available). Resolve
                    // transport methods at the moment they are used so a
                    // captured pre-grant runtime cannot silently strand a
                    // foreground request or event port.
                    const roots = [
                        globalThis.chrome,
                        globalThis.browser,
                        primaryRoot,
                        nativeChrome,
                        nativeBrowser
                    ];
                    const seen = new Set();
                    for (const root of roots) {
                        let runtime;
                        try { runtime = root?.runtime; } catch {}
                        if (!runtime || seen.has(runtime)) continue;
                        seen.add(runtime);
                        try {
                            if (typeof runtime[methodName] === "function") {
                                return runtime;
                            }
                        } catch {}
                    }
                    return undefined;
                };
                // Chrome reports a failed callback-form call by publishing
                // `runtime.lastError` for exactly the duration of that
                // callback, and logging "Unchecked runtime.lastError" when the
                // callback never reads it. Handing a callback `undefined` and
                // discarding the reason — the previous behavior — left an
                // extension unable to tell a failure from an empty result, and
                // left the failure invisible in the console.
                let missingLastErrorTargetLogged = false;
                // Assigned by the diagnostics channel below, which installs
                // only in privileged extension contexts. A context without one
                // — every content script — reports nothing.
                let reportRuntimeDiagnostics = () => {};
                // Assigned only when console capture is on. Message tracing
                // is the same instrument as console capture — it makes an
                // invisible failure readable — so it rides the same gate, and
                // with that gate off this stays a no-op that nothing calls.
                let reportRuntimeTrace = () => {};
                const lastErrorTargets = () => {
                    const targets = [];
                    const seen = new Set();
                    for (const root of [
                        globalThis.chrome,
                        globalThis.browser,
                        primaryRoot,
                        nativeChrome,
                        nativeBrowser
                    ]) {
                        let runtime;
                        try { runtime = root?.runtime; } catch {}
                        if (!runtime || seen.has(runtime)) continue;
                        seen.add(runtime);
                        targets.push(runtime);
                    }
                    return targets;
                };
                const invokeCallbackWithLastError = (
                    callback,
                    message,
                    value
                ) => {
                    if (typeof callback !== "function") return;
                    const lastError = Object.freeze({
                        message: String(message)
                    });
                    let wasRead = false;
                    const published = [];
                    for (const target of lastErrorTargets()) {
                        let previous;
                        try {
                            previous = Reflect.getOwnPropertyDescriptor(
                                target,
                                "lastError"
                            );
                            Object.defineProperty(target, "lastError", {
                                get() {
                                    wasRead = true;
                                    return lastError;
                                },
                                configurable: true,
                                enumerable: previous?.enumerable ?? true
                            });
                        } catch {
                            continue;
                        }
                        published.push([target, previous]);
                    }
                    if (
                        published.length === 0
                        && !missingLastErrorTargetLogged
                    ) {
                        missingLastErrorTargetLogged = true;
                        try {
                            console.warn(
                                "Crest could not publish runtime.lastError on this extension runtime; failed callbacks are reported on the console instead."
                            );
                        } catch {}
                    }
                    try {
                        callback(value);
                    } finally {
                        for (const [target, previous] of published) {
                            try {
                                if (previous) {
                                    Object.defineProperty(
                                        target,
                                        "lastError",
                                        previous
                                    );
                                } else {
                                    delete target.lastError;
                                }
                            } catch {}
                        }
                        if (!wasRead) {
                            const uncheckedMessage =
                                `Unchecked runtime.lastError: ${lastError.message}`;
                            // Reported before the console call, so the console
                            // capture wrapper's copy of the same text dedupes
                            // against this one rather than doubling it.
                            reportRuntimeDiagnostics(
                                "lastError",
                                uncheckedMessage
                            );
                            try {
                                console.error(uncheckedMessage);
                            } catch {}
                        }
                    }
                };
                const declaredManifest = Object.freeze(\(manifestLiteral));
                const backgroundPagePath =
                    declaredManifest.background?.page;
                const isDeclaredBackgroundPage =
                    typeof backgroundPagePath === "string"
                    && String(globalThis.location?.href ?? "")
                        .split("#", 1)[0]
                    === new URL(backgroundPagePath, extensionBaseURL).href;
                const isGeneratedBackgroundPage =
                    Array.isArray(declaredManifest.background?.scripts)
                    && String(globalThis.location?.pathname ?? "")
                        .endsWith("/_generated_background_page.html");
                const isBackgroundContext =
                    isBackgroundWorker
                    || isDeclaredBackgroundPage
                    || isGeneratedBackgroundPage;
                const hasMV3ServiceWorker =
                    declaredManifest.manifest_version === 3
                    && typeof declaredManifest.background?.service_worker
                        === "string";
                // The environment the PREPARED background runs in. A
                // dual-environment manifest still declares a service worker,
                // but preparation collapses it to a background document, so
                // the authored manifest cannot answer who owns durable events.
                const backgroundEnvironment = \(javascriptStringLiteral(backgroundEnvironment));
                const compatibilityPermissionNames = new Set(
                    \(compatibilityPermissionsLiteral)
                );
                const namespaceRoutes = Object.freeze(
                    \(namespaceRoutesLiteral)
                );
                const namespacePermissions = Object.freeze(
                    \(namespacePermissionsLiteral)
                );
                const namespaceManifestKeys = Object.freeze(\(namespaceManifestKeysLiteral));
                const memberRoutes = Object.freeze(\(memberRoutesLiteral));
                const namespaceEventMembers = Object.freeze(
                    \(namespaceEventMembersLiteral)
                );
                const backgroundWorkerHiddenMembers = Object.freeze(
                    \(backgroundWorkerHiddenMembersLiteral)
                );
                const eventMembersOf = (namespace) =>
                    namespaceEventMembers[namespace] ?? [];
                const backgroundWorkerHiddenMembersOf = (namespace) =>
                    new Set(backgroundWorkerHiddenMembers[namespace] ?? []);
                const namespaceProcesses = Object.freeze(
                    \(namespaceProcessesLiteral)
                );
                const memberProcesses = Object.freeze(
                    \(memberProcessesLiteral)
                );
                // Every member the reference schema defines for a namespace
                // Crest emulates. A portable package tests the namespace and
                // then uses the schema in the same expression, so a namespace
                // object holding only the members Crest implements turns a
                // successful feature detection into a `TypeError` thrown
                // inside whatever awaited it. The runtime therefore publishes
                // this whole list and fills the unimplemented half with
                // honest placeholders — see `presenceOnlyMember`.
                const emulatedSurface = Object.freeze(
                    \(emulatedSurfaceLiteral)
                );
                const executionProcess = isBackgroundContext
                    ? "background"
                    : isPrivilegedExtensionContext
                        ? "extensionPage"
                        : "contentScript";
                const supportsProcess = (processes) =>
                    Array.isArray(processes)
                    && processes.includes(executionProcess);
                const declaredPermissionNames = new Set(
                    [
                        ...(Array.isArray(declaredManifest.permissions)
                            ? declaredManifest.permissions
                            : []),
                        ...(Array.isArray(
                            declaredManifest.optional_permissions
                        )
                            ? declaredManifest.optional_permissions
                            : [])
                    ].filter(
                        (permission) => typeof permission === "string"
                    )
                );
                // Chrome defines a permission-gated namespace only when the
                // package declared one of its permissions, and portable
                // extensions feature-detect exactly that. Publishing an
                // emulated namespace nobody asked for hands an extension an
                // API whose every call the capability broker denies. Optional
                // permissions count: Chrome exposes the namespace before the
                // grant and fails the individual calls until it arrives.
                const namespaceIsDeclared = (namespace) => {
                    if (namespace === "sidePanel" && declaredManifest.manifest_version !== 3) return false;
                    const permissions = namespacePermissions[namespace] ?? [];
                    const manifestKeys = namespaceManifestKeys[namespace] ?? [];
                    if (permissions.length === 0 && manifestKeys.length === 0) return true;
                    return permissions.some(
                        (permission) =>
                            declaredPermissionNames.has(permission)
                    ) || manifestKeys.some((key) => Object.hasOwn(declaredManifest, key));
                };
                const namespaceUsesCompatibility = (namespace) =>
                    namespaceIsDeclared(namespace)
                    && supportsProcess(namespaceProcesses[namespace])
                    && (
                        namespaceRoutes[namespace] === "nativePatched"
                        || namespaceRoutes[namespace] === "emulated"
                    );
                // `presenceOnly` installs like an emulation — Crest supplies
                // the object — but it does not own the contract: see
                // `crestOwnsPath` below, where a native implementation still
                // displaces the placeholder.
                const memberUsesCompatibility = (path) =>
                    supportsProcess(memberProcesses[path])
                    && (
                        memberRoutes[path] === "nativePatched"
                        || memberRoutes[path] === "emulated"
                        || memberRoutes[path] === "presenceOnly"
                    );
                // Who wins is a routing decision, not an accident of which
                // properties WebKit happens to define today. `emulated` means
                // Crest's implementation IS the contract: it must replace a
                // native property that appears in a later OS release, which is
                // the entire reason the route exists. Every other route lets
                // the native implementation stand and fills only what is
                // missing.
                const routeFor = (path) =>
                    memberRoutes[path] ?? namespaceRoutes[path];
                const crestOwnsPath = (path) => routeFor(path) === "emulated";
                // A namespace Crest owns outright must never be satisfied by
                // copying WebKit's implementation across the `chrome`/`browser`
                // roots, and a namespace routed `unavailable` must never be
                // aliased into existence at all.
                const namespaceIsAliasable = (namespace) =>
                    namespaceRoutes[namespace] !== "emulated"
                    && namespaceRoutes[namespace] !== "unavailable";
                const extensionID = \(javascriptStringLiteral(runtimeIdentity.extensionID));
                const failsWorkerWebSockets = \(failsWorkerWebSockets ? "true" : "false");
                const scopedCompatibilityAPIName = \(javascriptStringLiteral(scopedCompatibilityAPIName));
                const capabilityBrokerHost = \(javascriptStringLiteral(
                    ProductIdentity.serviceNamespace
                        + ".webextension-compatibility"
                ));
                const fallbackResourceURL = (path = "") => new URL(
                    String(path),
                    extensionBaseURL
                ).href;

                // Chrome records an extension's uncaught exceptions and
                // unhandled promise rejections on the extension's own error
                // page. WebKit reports only what an API callback throws, so a
                // popup that dies mid-render — Bitwarden's, after a two-factor
                // sign-in — leaves nothing behind unless someone happened to
                // have Web Inspector attached. This channel reports them to
                // Crest instead.
                //
                // It is telemetry from the extension's own code, so it must
                // never change what that code observes: every send is
                // best-effort, an absent transport is not an error, nothing
                // here throws or rejects, and the channel never reports its
                // own failures. Content scripts install nothing at all — they
                // run on the page's origin, where the page itself would be
                // handed the reports.
                const capturesExtensionConsole = \(enablesConsoleCapture ? "true" : "false");
                const diagnosticsReportLimit = 20;
                const diagnosticsConsoleReportLimit = 200;
                const diagnosticsTraceReportLimit = 2000;
                const diagnosticsDedupeWindow = 1000;
                const diagnosticsMessageLimit = 2000;
                const installDiagnosticsChannel = () => {
                    if (!isPrivilegedExtensionContext) return;
                    let reportCount = 0;
                    let consoleReportCount = 0;
                    let traceReportCount = 0;
                    let reportedSuppression = false;
                    let reportedConsoleSuppression = false;
                    let reportedTraceSuppression = false;
                    let isReporting = false;
                    const recentReports = new Map();
                    const diagnosticsSource = () => {
                        try {
                            const href = String(
                                globalThis.location?.href ?? ""
                            );
                            return href === "" ? "worker" : href;
                        } catch {
                            return "worker";
                        }
                    };
                    const boundedText = (value) => {
                        let text;
                        try {
                            text = typeof value === "string"
                                ? value
                                : String(value ?? "");
                        } catch {
                            return "";
                        }
                        return text.length > diagnosticsMessageLimit
                            ? text.slice(0, diagnosticsMessageLimit)
                            : text;
                    };
                    const post = (report) => {
                        // Resolve the transport at send time, exactly as
                        // `requestCapability` does: WebKit can replace the
                        // runtime facade after this script starts. Unlike
                        // `requestCapability`, a missing transport is silent.
                        const runtime = nativeRuntimeWithMethod(
                            "sendNativeMessage"
                        );
                        const sendNativeMessage = runtime?.sendNativeMessage;
                        if (typeof sendNativeMessage !== "function") return;
                        try {
                            const returned = Reflect.apply(
                                sendNativeMessage,
                                runtime,
                                [capabilityBrokerHost, report]
                            );
                            // A refused diagnostics send must not become an
                            // unhandled rejection of its own.
                            if (returned?.then instanceof Function) {
                                returned.then(() => {}, () => {});
                            }
                        } catch {}
                    };
                    // Chrome collapses a burst of identical errors, and an
                    // extension that throws inside a tight event handler would
                    // otherwise spend the whole budget on one fault.
                    const isRepeatedReport = (message, source, at) => {
                        const key = `${message}\\u0000${source}`;
                        const previous = recentReports.get(key);
                        if (
                            previous !== undefined
                            && at - previous < diagnosticsDedupeWindow
                        ) {
                            return true;
                        }
                        recentReports.set(key, at);
                        if (recentReports.size > 64) {
                            for (const staleKey of recentReports.keys()) {
                                recentReports.delete(staleKey);
                                if (recentReports.size <= 32) break;
                            }
                        }
                        return false;
                    };
                    const report = (kind, message, stack, lineno, colno) => {
                        if (isReporting) return;
                        isReporting = true;
                        try {
                            const at = Date.now();
                            const source = diagnosticsSource();
                            const reportedMessage = boundedText(message);
                            if (isRepeatedReport(reportedMessage, source, at)) {
                                return;
                            }
                            if (reportCount >= diagnosticsReportLimit) {
                                if (reportedSuppression) return;
                                reportedSuppression = true;
                                post({
                                    api: "diagnostics.report",
                                    kind: "suppressed",
                                    message: `Crest suppressed further reports from this extension context after ${diagnosticsReportLimit}.`,
                                    stack: "",
                                    source,
                                    lineno: 0,
                                    colno: 0,
                                    at
                                });
                                return;
                            }
                            reportCount += 1;
                            post({
                                api: "diagnostics.report",
                                kind,
                                message: reportedMessage,
                                stack: boundedText(stack),
                                source,
                                lineno: Number.isFinite(lineno) ? lineno : 0,
                                colno: Number.isFinite(colno) ? colno : 0,
                                at
                            });
                        } catch {
                        } finally {
                            isReporting = false;
                        }
                    };
                    // A hang throws nothing. Bitwarden's popup waits forever on
                    // a port reply while logging exactly why through
                    // `console.warn`, so console output is the only trace some
                    // failures leave. It is verbose, so a build opts in.
                    const reportConsole = (level, args) => {
                        if (isReporting) return;
                        isReporting = true;
                        try {
                            const at = Date.now();
                            const source = diagnosticsSource();
                            const message = boundedText(
                                Array.prototype.map.call(args, (value) => {
                                    if (typeof value === "string") return value;
                                    if (value instanceof Error) {
                                        return String(value.stack ?? value);
                                    }
                                    if (
                                        value !== null
                                        && typeof value === "object"
                                    ) {
                                        try {
                                            return JSON.stringify(value)
                                                ?? String(value);
                                        } catch {
                                            return String(value);
                                        }
                                    }
                                    return String(value);
                                }).join(" ")
                            );
                            if (message === "") return;
                            if (isRepeatedReport(message, source, at)) return;
                            if (
                                consoleReportCount
                                    >= diagnosticsConsoleReportLimit
                            ) {
                                if (reportedConsoleSuppression) return;
                                reportedConsoleSuppression = true;
                                post({
                                    api: "diagnostics.report",
                                    kind: "suppressed",
                                    message: `Crest suppressed further console output from this extension context after ${diagnosticsConsoleReportLimit}.`,
                                    stack: "",
                                    source,
                                    lineno: 0,
                                    colno: 0,
                                    at
                                });
                                return;
                            }
                            consoleReportCount += 1;
                            post({
                                api: "diagnostics.report",
                                kind: "console",
                                level,
                                message,
                                source,
                                at
                            });
                        } catch {
                        } finally {
                            isReporting = false;
                        }
                    };
                    try {
                        self.addEventListener("error", (event) => {
                            const error = event?.error;
                            report(
                                "error",
                                error?.message
                                    ?? event?.message
                                    ?? "Uncaught error",
                                error?.stack,
                                event?.lineno,
                                event?.colno
                            );
                        });
                    } catch {}
                    try {
                        self.addEventListener(
                            "unhandledrejection",
                            (event) => {
                                const reason = event?.reason;
                                report(
                                    "unhandledrejection",
                                    reason?.message
                                        ?? reason
                                        ?? "Unhandled promise rejection",
                                    reason?.stack,
                                    0,
                                    0
                                );
                            }
                        );
                    } catch {}
                    reportRuntimeDiagnostics = (kind, message) => {
                        report(kind, message, "", 0, 0);
                    };
                    if (!capturesExtensionConsole) return;
                    // Deliberately not deduped: a repeated send is the signal.
                    // Bitwarden's popup sends `fullSync` and waits for a
                    // `syncCompleted` broadcast the worker sends back the same
                    // way, and when neither side logs, which half of that
                    // exchange never happened is the only question worth
                    // answering.
                    reportRuntimeTrace = (op, detail) => {
                        if (isReporting) return;
                        isReporting = true;
                        try {
                            const at = Date.now();
                            const source = diagnosticsSource();
                            if (
                                traceReportCount >= diagnosticsTraceReportLimit
                            ) {
                                if (reportedTraceSuppression) return;
                                reportedTraceSuppression = true;
                                post({
                                    api: "diagnostics.report",
                                    kind: "suppressed",
                                    message: `Crest suppressed further message traces from this extension context after ${diagnosticsTraceReportLimit}.`,
                                    stack: "",
                                    source,
                                    lineno: 0,
                                    colno: 0,
                                    at
                                });
                                return;
                            }
                            traceReportCount += 1;
                            let rendered;
                            try {
                                rendered = JSON.stringify(detail) ?? "";
                            } catch {
                                rendered = "";
                            }
                            post({
                                api: "diagnostics.report",
                                kind: "trace",
                                op: boundedText(op),
                                message: boundedText(`${op} ${rendered}`),
                                source,
                                at
                            });
                        } catch {
                        } finally {
                            isReporting = false;
                        }
                    };
                    const consoleObject = globalThis.console;
                    if (!consoleObject) return;
                    for (const level of ["error", "warn", "info"]) {
                        let original;
                        try {
                            original = consoleObject[level];
                        } catch {}
                        if (typeof original !== "function") continue;
                        const wrapper = function (...args) {
                            try {
                                reportConsole(level, args);
                            } catch {}
                            return Reflect.apply(original, this, args);
                        };
                        try {
                            Object.defineProperty(consoleObject, level, {
                                value: wrapper,
                                configurable: true,
                                writable: true,
                                enumerable: false
                            });
                        } catch {}
                    }
                };
                installDiagnosticsChannel();

                const installChromiumNavigatorFamilyMarker = () => {
                    if (!appendsChromiumNavigatorFamilyMarker) return;
                    const navigatorObject = globalThis.navigator;
                    if (!navigatorObject) return;
                    const appendMarker = (name) => {
                        let nativeValue;
                        try { nativeValue = navigatorObject[name]; } catch {}
                        if (
                            typeof nativeValue !== "string"
                            || /\\b(?:Chrome|Chromium)[/]/.test(nativeValue)
                        ) {
                            return;
                        }
                        const descriptor = {
                            value: `${nativeValue} Chrome/`,
                            configurable: true,
                            enumerable: true
                        };
                        try {
                            Object.defineProperty(
                                navigatorObject,
                                name,
                                descriptor
                            );
                            return;
                        } catch {}
                        try {
                            Object.defineProperty(
                                Object.getPrototypeOf(navigatorObject),
                                name,
                                descriptor
                            );
                        } catch {}
                    };
                    appendMarker("userAgent");
                    appendMarker("appVersion");
                };

                installChromiumNavigatorFamilyMarker();

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

            \(workerWebSocketScript)

                const topFrameMessageTransportKey =
                    "__crestWebExtensionTopFrameMessage";
                // Everything below to `traceRuntimeMessaging` is inert unless
                // console capture is on: each caller checks the gate first.
                // A content script's traffic is the extension's too, and on a
                // busy site it is almost all of it: Bitwarden's page scripts
                // spend a `collectPageDetailsResponse` and a
                // `checkIsFieldCurrentlyFocused` per field, which exhausted
                // the whole trace budget inside a minute and buried the
                // popup↔worker exchange the trace exists to see. Only
                // extension-origin senders are traced.
                const traceExtensionOriginPrefix =
                    extensionBaseURL.replace(/[/]+$/, "");
                const traceIsExtensionOriginSender = (sender) => {
                    if (!sender || typeof sender !== "object") return true;
                    let isAttributed = false;
                    for (const key of ["origin", "url"]) {
                        let value;
                        try { value = sender[key]; } catch {}
                        if (typeof value !== "string" || value === "") {
                            continue;
                        }
                        isAttributed = true;
                        if (
                            value === traceExtensionOriginPrefix
                            || value.startsWith(
                                `${traceExtensionOriginPrefix}/`
                            )
                        ) {
                            return true;
                        }
                    }
                    // An unattributed delivery is kept. The noise this filter
                    // exists to drop always names a page origin, and dropping
                    // the unknown case could hide the exchange being hunted.
                    return !isAttributed;
                };
                const traceErrorText = (error) => {
                    try {
                        return String(error?.message ?? error ?? "");
                    } catch {
                        return "";
                    }
                };
                // Names the message without quoting its contents. A password
                // manager's traffic carries vault data, so a trace records the
                // command and the shape — the top-level keys — and no values.
                const traceMessageSummary = (value) => {
                    if (value === null || typeof value !== "object") {
                        return typeof value;
                    }
                    let name = "(unnamed)";
                    for (const key of ["command", "kind", "type", "name"]) {
                        let candidate;
                        try { candidate = value[key]; } catch {}
                        if (typeof candidate === "string" && candidate !== "") {
                            name = `${key}=${candidate}`;
                            break;
                        }
                    }
                    // Bitwarden pairs a request with its response by
                    // `requestId`, which is what makes one `fullSync` round
                    // trip followable across the popup and the worker.
                    let requestId;
                    try {
                        const candidate = value.requestId;
                        if (
                            typeof candidate === "string"
                            || typeof candidate === "number"
                        ) {
                            requestId = String(candidate);
                        }
                    } catch {}
                    let keys = [];
                    try {
                        keys = Object.keys(value).slice(0, 24);
                    } catch {}
                    const identity = requestId === undefined
                        ? name
                        : `${name} requestId=${requestId}`;
                    return `${identity} keys:[${keys.join(",")}]`;
                };
                const traceSenderSummary = (sender) => {
                    if (!sender || typeof sender !== "object") return undefined;
                    const summary = {};
                    try {
                        if (typeof sender.origin === "string") {
                            summary.origin = sender.origin;
                        }
                    } catch {}
                    try {
                        if (sender.frameId !== undefined) {
                            summary.frameId = Number(sender.frameId);
                        }
                    } catch {}
                    try {
                        summary.hasTab = sender.tab !== undefined
                            && sender.tab !== null;
                    } catch {}
                    return summary;
                };
                const tracePortName = (value) => {
                    try {
                        const name = value?.name;
                        return typeof name === "string" ? name : "";
                    } catch {
                        return "";
                    }
                };
                const tracePortNameFromArguments = (args) => {
                    for (const value of args) {
                        if (value === null || typeof value !== "object") {
                            continue;
                        }
                        const name = tracePortName(value);
                        if (name !== "") return name;
                    }
                    return "";
                };
                // `sendMessage` accepts an optional leading extension ID.
                const traceSentMessage = (args) => (
                    typeof args[0] === "string" && args.length > 1
                        ? args[1]
                        : args[0]
                );
                const tracedMessagingFunctions = new WeakSet();
                // Wraps the two entry points an extension sends through,
                // without touching what either one means: the receiver is
                // forwarded verbatim (WebKit's implementations check it), the
                // native return value is handed back unchanged, and a second
                // pass over the same runtime re-wraps nothing.
                const traceRuntimeMessaging = (nativeRuntime) => {
                    for (const property of ["sendMessage", "connect"]) {
                        let native;
                        let descriptor;
                        try {
                            native = nativeRuntime[property];
                            descriptor = Reflect.getOwnPropertyDescriptor(
                                nativeRuntime,
                                property
                            );
                        } catch {}
                        if (
                            typeof native !== "function"
                            || tracedMessagingFunctions.has(native)
                        ) {
                            continue;
                        }
                        const op = property;
                        const wrapper = function (...args) {
                            const detail = {
                                context: executionProcess,
                                summary: op === "connect"
                                    ? tracePortNameFromArguments(args)
                                    : traceMessageSummary(
                                        traceSentMessage(args)
                                    )
                            };
                            reportRuntimeTrace(op, detail);
                            const result = Reflect.apply(native, this, args);
                            if (result?.then instanceof Function) {
                                // The caller gets the ORIGINAL promise back;
                                // these observers only watch it. Attaching
                                // them does mark it handled, so while tracing
                                // is on a rejection the extension ignores is
                                // reported here instead of as an unhandled
                                // rejection. That trade is confined to a
                                // console-capture build.
                                try {
                                    result.then(
                                        () => reportRuntimeTrace(
                                            `${op}Resolved`,
                                            detail
                                        ),
                                        (error) => reportRuntimeTrace(
                                            `${op}Rejected`,
                                            {
                                                ...detail,
                                                error: traceErrorText(error)
                                            }
                                        )
                                    );
                                } catch {}
                            }
                            return result;
                        };
                        tracedMessagingFunctions.add(wrapper);
                        try {
                            Object.defineProperty(nativeRuntime, property, {
                                value: wrapper,
                                writable: true,
                                configurable: true,
                                enumerable: descriptor?.enumerable ?? true
                            });
                        } catch {}
                    }
                };
                const normalizedRuntimeMessageEvents = new WeakSet();
                const normalizeRuntimeMessageEvent = (nativeEvent) => {
                    if (
                        !nativeEvent
                        || normalizedRuntimeMessageEvents.has(nativeEvent)
                    ) {
                        return;
                    }
                    const nativeAddListener = nativeEvent.addListener;
                    const nativeRemoveListener = nativeEvent.removeListener;
                    const nativeHasListener = nativeEvent.hasListener;
                    const nativeHasListeners = nativeEvent.hasListeners;
                    if (
                        typeof nativeAddListener !== "function"
                        || typeof nativeRemoveListener !== "function"
                    ) {
                        return;
                    }

                    const wrappedListeners = new WeakMap();
                    // Maintained only while tracing. A count is what
                    // separates "no listener was ever attached" from "a
                    // listener ran and claimed nothing".
                    const tracedMessageListeners = new Set();
                    const wrapperFor = (listener) => {
                        let wrapped = wrappedListeners.get(listener);
                        if (wrapped) return wrapped;
                        wrapped = (message, sender) => {
                            let deliveredMessage = message;
                            if (
                                message
                                && typeof message === "object"
                                && message[topFrameMessageTransportKey] === true
                            ) {
                                if (
                                    typeof globalThis.document !== "undefined"
                                    && globalThis.top !== globalThis
                                ) {
                                    return false;
                                }
                                deliveredMessage = message.message;
                            }
                            const isTracedDelivery =
                                capturesExtensionConsole
                                && traceIsExtensionOriginSender(sender);
                            if (isTracedDelivery) {
                                reportRuntimeTrace("onMessage", {
                                    context: executionProcess,
                                    summary: traceMessageSummary(
                                        deliveredMessage
                                    ),
                                    sender: traceSenderSummary(sender),
                                    listeners: tracedMessageListeners.size
                                });
                            }
                            let didRespond = false;
                            let resolveResponse;
                            const response = new Promise((resolve) => {
                                resolveResponse = resolve;
                            });
                            const sendResponse = (value) => {
                                didRespond = true;
                                resolveResponse(value);
                                return true;
                            };
                            const result = listener(
                                deliveredMessage,
                                sender,
                                sendResponse
                            );
                            if (isTracedDelivery) {
                                // Whether a logical listener claimed the
                                // response — returned a Promise, returned
                                // true, or answered synchronously. A delivery
                                // nobody claims is precisely the shape of a
                                // sender that waits forever.
                                const settled =
                                    result?.then instanceof Function
                                        ? result
                                        : result === true || didRespond
                                            ? response
                                            : undefined;
                                reportRuntimeTrace("onMessageResult", {
                                    context: executionProcess,
                                    kept: settled !== undefined
                                });
                                const responded = () => reportRuntimeTrace(
                                    "onMessageResponded",
                                    { context: executionProcess }
                                );
                                try {
                                    settled?.then(responded, responded);
                                } catch {}
                            }
                            if (
                                result
                                && typeof result.then === "function"
                            ) {
                                return result;
                            }
                            // Chrome keeps the message channel alive when a
                            // callback listener returns true. WebKit can close
                            // that channel at the end of the event dispatch,
                            // completing the sender with no value before an
                            // asynchronously starting worker answers. A
                            // returned Promise expresses the same lifetime in
                            // the browser-neutral WebExtension contract.
                            if (result === true || didRespond) {
                                return response;
                            }
                            return result;
                        };
                        wrappedListeners.set(listener, wrapped);
                        return wrapped;
                    };
                    const addListener = (listener) => {
                        if (typeof listener !== "function") return;
                        if (capturesExtensionConsole) {
                            tracedMessageListeners.add(listener);
                        }
                        return Reflect.apply(
                            nativeAddListener,
                            nativeEvent,
                            [wrapperFor(listener)]
                        );
                    };
                    const removeListener = (listener) => {
                        if (capturesExtensionConsole) {
                            tracedMessageListeners.delete(listener);
                        }
                        const wrapped = wrappedListeners.get(listener)
                            ?? listener;
                        const result = Reflect.apply(
                            nativeRemoveListener,
                            nativeEvent,
                            [wrapped]
                        );
                        wrappedListeners.delete(listener);
                        return result;
                    };
                    const hasListener = (listener) => {
                        if (typeof nativeHasListener !== "function") {
                            return wrappedListeners.has(listener);
                        }
                        return Reflect.apply(
                            nativeHasListener,
                            nativeEvent,
                            [wrappedListeners.get(listener) ?? listener]
                        );
                    };
                    const hasListeners = () =>
                        typeof nativeHasListeners === "function"
                            ? Reflect.apply(
                                nativeHasListeners,
                                nativeEvent,
                                []
                            )
                            : false;
                    if (
                        installEventFacade(nativeEvent, {
                            addListener,
                            removeListener,
                            hasListener,
                            hasListeners
                        })
                    ) {
                        normalizedRuntimeMessageEvents.add(nativeEvent);
                    }
                };
                const normalizedRuntimeConnectEvents = new WeakSet();
                const normalizeRuntimeConnectEvent = (nativeEvent) => {
                    if (
                        !isBackgroundWorker
                        || !nativeEvent
                        || normalizedRuntimeConnectEvents.has(nativeEvent)
                    ) {
                        return;
                    }
                    const nativeAddListener = nativeEvent.addListener;
                    if (typeof nativeAddListener !== "function") return;

                    // WebKit rejects runtime.connect as soon as a lazily
                    // started background worker has no onConnect listener.
                    // Chromium retains the connection while that worker
                    // bootstraps, so extensions may attach their application
                    // listener after asynchronous state setup. Install one
                    // native listener before the authored worker code, retain
                    // its early ports, and replay each port once when the
                    // logical listener arrives. Persistent MV2 background
                    // pages already own a live native event and must retain it
                    // unchanged.
                    const listeners = new Set();
                    const activePorts = new Set();
                    const deliveredPorts = new WeakMap();
                    const deliver = (listener, port) => {
                        let delivered = deliveredPorts.get(listener);
                        if (!delivered) {
                            delivered = new WeakSet();
                            deliveredPorts.set(listener, delivered);
                        }
                        if (delivered.has(port)) return;
                        delivered.add(port);
                        try { listener(port); } catch {}
                    };
                    const bridge = (port) => {
                        if (!port) return;
                        if (
                            capturesExtensionConsole
                            && traceIsExtensionOriginSender(port?.sender)
                        ) {
                            reportRuntimeTrace("onConnect", {
                                context: executionProcess,
                                summary: tracePortName(port),
                                sender: traceSenderSummary(port?.sender),
                                listeners: listeners.size
                            });
                        }
                        activePorts.add(port);
                        const remove = () => {
                            activePorts.delete(port);
                            try {
                                port.onDisconnect?.removeListener(remove);
                            } catch {}
                        };
                        try {
                            port.onDisconnect?.addListener(remove);
                        } catch {}
                        for (const listener of Array.from(listeners)) {
                            deliver(listener, port);
                        }
                    };
                    Reflect.apply(
                        nativeAddListener,
                        nativeEvent,
                        [bridge]
                    );
                    const addListener = (listener) => {
                        if (typeof listener !== "function") return;
                        listeners.add(listener);
                        for (const port of Array.from(activePorts)) {
                            deliver(listener, port);
                        }
                    };
                    const removeListener = (listener) => {
                        listeners.delete(listener);
                        deliveredPorts.delete(listener);
                    };
                    const hasListener = (listener) =>
                        listeners.has(listener);
                    const hasListeners = () => listeners.size > 0;
                    if (
                        installEventFacade(nativeEvent, {
                            addListener,
                            removeListener,
                            hasListener,
                            hasListeners
                        })
                    ) {
                        normalizedRuntimeConnectEvents.add(nativeEvent);
                    }
                };
                const normalizedRuntimes = new WeakSet();
                const normalizeRuntime = (nativeRuntime) => {
                    if (
                        !namespaceUsesCompatibility("runtime")
                        || !nativeRuntime
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
                            writable: true,
                            configurable: true,
                            enumerable: descriptor?.enumerable ?? true
                        });
                    } catch {
                        try { nativeRuntime.getURL = getURL; } catch {}
                    }
                    // Debug-build only, and the last thing installed on the
                    // native runtime so it wraps WebKit's own implementations
                    // rather than a compatibility shim.
                    if (capturesExtensionConsole) {
                        try {
                            traceRuntimeMessaging(nativeRuntime);
                        } catch {}
                    }
                    try {
                        normalizeRuntimeMessageEvent(nativeRuntime.onMessage);
                    } catch {}
                    try {
                        normalizeRuntimeConnectEvent(nativeRuntime.onConnect);
                    } catch {}
                };

                const normalizedTabsNamespaces = new WeakMap();
                const normalizeTabsNamespace = (nativeTabs) => {
                    if (
                        !memberUsesCompatibility("tabs.get")
                        && !memberUsesCompatibility("tabs.query")
                        && !memberUsesCompatibility("tabs.sendMessage")
                        && !memberUsesCompatibility("tabs.group")
                        && !memberUsesCompatibility("tabs.ungroup")
                    ) {
                        return nativeTabs;
                    }
                    if (!nativeTabs) return nativeTabs;
                    if (normalizedTabsNamespaces.has(nativeTabs)) {
                        return normalizedTabsNamespaces.get(nativeTabs);
                    }
                    let nativeGet;
                    let nativeQuery;
                    let nativeSendMessage;
                    try { nativeGet = nativeTabs.get; } catch {}
                    try { nativeQuery = nativeTabs.query; } catch {}
                    try { nativeSendMessage = nativeTabs.sendMessage; } catch {}

                    // WKWebExtensionTab has no discarded-state delegate. Crest
                    // deliberately returns a zero size when a session tab has
                    // no resident WKWebView; project that host invariant into
                    // the Chromium/Firefox Tab.discarded contract so queries
                    // do not send script and frame operations to unloaded tabs.
                    //
                    // `groupId` is projected the same way and for the same
                    // reason: WebKit has no tab-group concept, Crest's
                    // registry does, and Chrome puts the field on every tab
                    // object. `TAB_GROUP_ID_NONE` is the honest answer for a
                    // tab in no group, which is every tab until some
                    // extension calls `tabs.group`.
                    const normalizeTab = (tab) => {
                        if (!tab || typeof tab !== "object") return tab;
                        const grouped =
                            typeof tab.groupId === "number"
                                ? tab
                                : {
                                    ...tab,
                                    groupId: tabGroupsProjectTab(tab)
                                };
                        if (typeof grouped.discarded === "boolean") {
                            return grouped;
                        }
                        const hasSize =
                            typeof grouped.width === "number"
                            && typeof grouped.height === "number";
                        if (!hasSize) return grouped;
                        return {
                            ...grouped,
                            discarded:
                                grouped.width === 0 && grouped.height === 0,
                            autoDiscardable:
                                typeof grouped.autoDiscardable === "boolean"
                                    ? grouped.autoDiscardable
                                    : true
                        };
                    };
                    const transformCallbackResult = (
                        inputArguments,
                        transform
                    ) => {
                        const args = Array.from(inputArguments);
                        const callback = typeof args.at(-1) === "function"
                            ? args.pop()
                            : undefined;
                        return { args, callback, transform };
                    };
                    const invokeTransformed = (
                        nativeMethod,
                        inputArguments,
                        transform
                    ) => {
                        const invocation = transformCallbackResult(
                            inputArguments,
                            transform
                        );
                        if (invocation.callback) {
                            invocation.args.push((value) =>
                                invocation.callback(invocation.transform(value))
                            );
                            return Reflect.apply(
                                nativeMethod,
                                nativeTabs,
                                invocation.args
                            );
                        }
                        const result = Reflect.apply(
                            nativeMethod,
                            nativeTabs,
                            invocation.args
                        );
                        return result && typeof result.then === "function"
                            ? result.then(invocation.transform)
                            : invocation.transform(result);
                    };

                    const get = typeof nativeGet === "function"
                        && memberUsesCompatibility("tabs.get")
                        ? (...inputArguments) => tabGroupsWithMembership(
                            typeof inputArguments.at(-1) === "function",
                            () => invokeTransformed(
                                nativeGet,
                                inputArguments,
                                normalizeTab
                            )
                        )
                        : nativeGet;
                    const query = typeof nativeQuery === "function"
                        && memberUsesCompatibility("tabs.query")
                        ? (...inputArguments) => {
                            const args = Array.from(inputArguments);
                            const callback = typeof args.at(-1) === "function"
                                ? args.pop()
                                : undefined;
                            const options = args[0]
                                && typeof args[0] === "object"
                                ? args[0]
                                : undefined;
                            const requested = options
                                ? options.discarded
                                : undefined;
                            // Reads `groupId` and switches the `Tab.groupId`
                            // mirror on: a package filtering by group has
                            // asked for the field by name. WebKit knows
                            // neither key, so both are stripped before the
                            // native query and applied to its result here.
                            const requestedGroup =
                                tabGroupsQueryFilter(options);
                            if (
                                typeof requested === "boolean"
                                || requestedGroup !== undefined
                            ) {
                                args[0] = { ...options };
                                if (typeof requested === "boolean") {
                                    delete args[0].discarded;
                                }
                                delete args[0].groupId;
                            }
                            const transform = (tabs) => {
                                if (!Array.isArray(tabs)) return tabs;
                                let normalized = tabs.map(normalizeTab);
                                if (typeof requested === "boolean") {
                                    normalized = normalized.filter(
                                        (tab) => tab.discarded === requested
                                    );
                                }
                                if (requestedGroup !== undefined) {
                                    normalized = normalized.filter(
                                        (tab) => tab.groupId === requestedGroup
                                    );
                                }
                                return normalized;
                            };
                            if (callback) args.push(callback);
                            return tabGroupsWithMembership(
                                callback !== undefined,
                                () => invokeTransformed(
                                    nativeQuery,
                                    args,
                                    transform
                                )
                            );
                        }
                        : nativeQuery;

                    const sendMessage = (...inputArguments) => {
                        const args = Array.from(inputArguments);
                        const callback = typeof args.at(-1) === "function"
                            ? args.pop()
                            : undefined;
                        const tabID = args[0];
                        const message = args[1];
                        const options = args[2];
                        if (
                            !options
                            || typeof options !== "object"
                            || options.frameId !== 0
                        ) {
                            return Reflect.apply(
                                nativeSendMessage,
                                nativeTabs,
                                inputArguments
                            );
                        }

                        // WebKit 27 never settles a worker-to-content message
                        // explicitly targeting frame zero. Sending without its
                        // broken top-frame selector does settle, but would also
                        // broadcast to subframes. Wrap the payload so the
                        // normalized runtime event admits it only in the top
                        // frame, preserving Chrome's frame-targeting contract.
                        const remainingOptions = { ...options };
                        delete remainingOptions.frameId;
                        const transportedMessage = {
                            [topFrameMessageTransportKey]: true,
                            message
                        };
                        const nativeArguments = [tabID, transportedMessage];
                        if (Object.keys(remainingOptions).length > 0) {
                            nativeArguments.push(remainingOptions);
                        }
                        if (callback) nativeArguments.push(callback);
                        return Reflect.apply(
                            nativeSendMessage,
                            nativeTabs,
                            nativeArguments
                        );
                    };
                    const overlays = new Map();
                    if (get !== nativeGet) overlays.set("get", get);
                    if (query !== nativeQuery) overlays.set("query", query);
                    if (
                        typeof nativeSendMessage === "function"
                        && memberUsesCompatibility("tabs.sendMessage")
                    ) {
                        overlays.set("sendMessage", sendMessage);
                    }
                    // Grouping has no WebKit implementation to patch, so
                    // these are installed outright rather than wrapped.
                    if (memberUsesCompatibility("tabs.group")) {
                        overlays.set("group", tabGroupsGroupTabs);
                    }
                    if (memberUsesCompatibility("tabs.ungroup")) {
                        overlays.set("ungroup", tabGroupsUngroupTabs);
                    }
                    if (overlays.size === 0) {
                        normalizedTabsNamespaces.set(nativeTabs, nativeTabs);
                        return nativeTabs;
                    }
                    const facade = namespaceFacade(
                        nativeTabs,
                        {},
                        overlays
                    );
                    normalizedTabsNamespaces.set(nativeTabs, facade);
                    normalizedTabsNamespaces.set(facade, facade);
                    return facade;
                };

                const normalizedWebNavigationNamespaces = new WeakMap();
                const normalizeWebNavigationNamespace = (
                    nativeWebNavigation,
                    nativeTabs
                ) => {
                    if (
                        !memberUsesCompatibility(
                            "webNavigation.getAllFrames"
                        )
                        || !nativeWebNavigation
                    ) {
                        return nativeWebNavigation;
                    }
                    if (
                        normalizedWebNavigationNamespaces.has(
                            nativeWebNavigation
                        )
                    ) {
                        return normalizedWebNavigationNamespaces.get(
                            nativeWebNavigation
                        );
                    }
                    let nativeGetAllFrames;
                    try {
                        nativeGetAllFrames =
                            nativeWebNavigation.getAllFrames;
                    } catch {}
                    if (typeof nativeGetAllFrames !== "function") {
                        normalizedWebNavigationNamespaces.set(
                            nativeWebNavigation,
                            nativeWebNavigation
                        );
                        return nativeWebNavigation;
                    }
                    const normalizedTabs =
                        normalizeTabsNamespace(nativeTabs);
                    const normalizedGet = normalizedTabs?.get;
                    const getTab = (tabID) => new Promise((resolve) => {
                        if (typeof normalizedGet !== "function") {
                            resolve(undefined);
                            return;
                        }
                        let settled = false;
                        const finish = (tab) => {
                            if (settled) return;
                            settled = true;
                            resolve(tab);
                        };
                        try {
                            const result = Reflect.apply(
                                normalizedGet,
                                normalizedTabs,
                                [tabID, finish]
                            );
                            if (result && typeof result.then === "function") {
                                result.then(finish, () => finish(undefined));
                            }
                        } catch {
                            finish(undefined);
                        }
                    });
                    const getAllFrames = (details, callback) => {
                        const tabID = details?.tabId;
                        if (typeof callback === "function") {
                            void getTab(tabID).then((tab) => {
                                // Chromium returns an undefined result for a
                                // valid discarded tab because it has no live
                                // WebContents/frame tree. WebKit instead turns
                                // a nil WKWebView into a runtime error.
                                if (tab?.discarded === true) {
                                    callback(undefined);
                                    return;
                                }
                                Reflect.apply(
                                    nativeGetAllFrames,
                                    nativeWebNavigation,
                                    [details, callback]
                                );
                            });
                            return;
                        }
                        return getTab(tabID).then((tab) => {
                            if (tab?.discarded === true) return undefined;
                            return Reflect.apply(
                                nativeGetAllFrames,
                                nativeWebNavigation,
                                [details]
                            );
                        });
                    };
                    const facade = namespaceFacade(
                        nativeWebNavigation,
                        {},
                        new Map([["getAllFrames", getAllFrames]])
                    );
                    normalizedWebNavigationNamespaces.set(
                        nativeWebNavigation,
                        facade
                    );
                    normalizedWebNavigationNamespaces.set(facade, facade);
                    return facade;
                };

                const normalizedWebRequestEvents = new WeakMap();
                const warnedBlockingWebRequestEvents = new Set();
                const normalizeWebRequestDetails = (details) => {
                    if (
                        !details
                        || typeof details !== "object"
                        || details.type !== "main_frame"
                        || details.parentFrameId === undefined
                        || details.parentFrameId === -1
                    ) {
                        return details;
                    }

                    // WebKit 27 maps every ResourceLoadInfo::Document to
                    // `main_frame`, including documents with a parent frame.
                    // Chromium and Firefox call those child-document loads
                    // `sub_frame`. Preserve the native frame identifiers and
                    // repair only the contradictory resource type before an
                    // extension evaluates its filtering policy.
                    return { ...details, type: "sub_frame" };
                };
                const normalizeWebRequestEvent = (nativeEvent, eventName) => {
                    if (!nativeEvent) return nativeEvent;
                    if (normalizedWebRequestEvents.has(nativeEvent)) {
                        return normalizedWebRequestEvents.get(nativeEvent);
                    }

                    let nativeAddListener;
                    let nativeRemoveListener;
                    let nativeHasListener;
                    let nativeHasListeners;
                    try {
                        nativeAddListener = nativeEvent.addListener;
                        nativeRemoveListener = nativeEvent.removeListener;
                        nativeHasListener = nativeEvent.hasListener;
                        nativeHasListeners = nativeEvent.hasListeners;
                    } catch {}
                    if (typeof nativeAddListener !== "function") {
                        normalizedWebRequestEvents.set(
                            nativeEvent,
                            nativeEvent
                        );
                        return nativeEvent;
                    }

                    const listeners = new WeakMap();
                    const wrappedListener = (listener) => {
                        if (typeof listener !== "function") return listener;
                        if (listeners.has(listener)) {
                            return listeners.get(listener);
                        }
                        const wrapped = (details, ...args) => Reflect.apply(
                            listener,
                            undefined,
                            [normalizeWebRequestDetails(details), ...args]
                        );
                        listeners.set(listener, wrapped);
                        return wrapped;
                    };
                    const addListener = (listener, ...args) => {
                        // WebKit registers a blocking listener and then
                        // ignores what it returns. Registration still buys the
                        // extension observation, so keep it — but say plainly
                        // that the request will not be cancelled, redirected,
                        // or have its headers rewritten. Silence here reads as
                        // a working content blocker that quietly blocks
                        // nothing.
                        const extraInfoSpec = args.find(Array.isArray);
                        if (
                            Array.isArray(extraInfoSpec)
                            && (extraInfoSpec.includes("blocking")
                                || extraInfoSpec.includes("asyncBlocking"))
                            && !warnedBlockingWebRequestEvents.has(eventName)
                        ) {
                            warnedBlockingWebRequestEvents.add(eventName);
                            try {
                                console.warn(
                                    `webRequest.${eventName}: WebKit does not consume blocking responses. The listener still observes requests, but its return value cannot cancel, redirect, or rewrite them.`
                                );
                            } catch {}
                        }
                        return Reflect.apply(
                            nativeAddListener,
                            nativeEvent,
                            [wrappedListener(listener), ...args]
                        );
                    };
                    const removeListener = (listener) => {
                        if (typeof nativeRemoveListener !== "function") {
                            return;
                        }
                        return Reflect.apply(
                            nativeRemoveListener,
                            nativeEvent,
                            [listeners.get(listener) ?? listener]
                        );
                    };
                    const hasListener = (listener) => {
                        if (typeof nativeHasListener !== "function") {
                            return false;
                        }
                        return Reflect.apply(
                            nativeHasListener,
                            nativeEvent,
                            [listeners.get(listener) ?? listener]
                        );
                    };
                    const hasListeners = () => {
                        if (typeof nativeHasListeners !== "function") {
                            return false;
                        }
                        return Reflect.apply(
                            nativeHasListeners,
                            nativeEvent,
                            []
                        );
                    };
                    const facade = {
                        addListener,
                        removeListener,
                        hasListener,
                        hasListeners
                    };

                    // Keep WebKit's native event object as the registered
                    // dispatch target. MV2 background pages resolve
                    // `browser.webRequest` through that live global, and a
                    // replacement JavaScript facade cannot receive native
                    // callbacks even though its methods look equivalent.
                    if (installEventFacade(nativeEvent, facade)) {
                        normalizedWebRequestEvents.set(
                            nativeEvent,
                            nativeEvent
                        );
                        return nativeEvent;
                    }

                    const event = Object.freeze(facade);
                    normalizedWebRequestEvents.set(nativeEvent, event);
                    normalizedWebRequestEvents.set(event, event);
                    return event;
                };
                const normalizedWebRequestNamespaces = new WeakMap();
                const normalizeWebRequestNamespace = (nativeWebRequest) => {
                    if (
                        !namespaceUsesCompatibility("webRequest")
                        || !nativeWebRequest
                    ) {
                        return nativeWebRequest;
                    }
                    if (
                        normalizedWebRequestNamespaces.has(nativeWebRequest)
                    ) {
                        return normalizedWebRequestNamespaces.get(
                            nativeWebRequest
                        );
                    }

                    const overlays = new Map();
                    // Derived from the matrix, which is also what decides
                    // which members are hidden from WebKit's surface before
                    // this context loads. A literal list here used to
                    // re-normalize `onAuthRequired` — an event the matrix
                    // hides precisely because Crest cannot honor a blocking
                    // credential prompt — and so handed it back to packages
                    // through the facade.
                    for (const property of eventMembersOf("webRequest")) {
                        let nativeEvent;
                        try { nativeEvent = nativeWebRequest[property]; } catch {}
                        const normalizedEvent = normalizeWebRequestEvent(
                            nativeEvent,
                            property
                        );
                        if (normalizedEvent !== nativeEvent) {
                            overlays.set(property, normalizedEvent);
                        }
                    }
                    if (overlays.size === 0) {
                        normalizedWebRequestNamespaces.set(
                            nativeWebRequest,
                            nativeWebRequest
                        );
                        return nativeWebRequest;
                    }

                    const facade = namespaceFacade(
                        nativeWebRequest,
                        {},
                        overlays
                    );
                    normalizedWebRequestNamespaces.set(
                        nativeWebRequest,
                        facade
                    );
                    normalizedWebRequestNamespaces.set(facade, facade);
                    return facade;
                };

                const normalizedI18nNamespaces = new WeakMap();
                const normalizeI18n = (nativeI18n) => {
                    if (!memberUsesCompatibility("i18n.getMessage")) {
                        return nativeI18n;
                    }
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
                            writable: true,
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
                // The object behind a `presenceOnly` route. Feature detection
                // and registration succeed — a portable package that guards on
                // `typeof event.addListener === "function"` takes the same
                // branch it takes in Chrome — but Crest has no source that can
                // fire it. Two things follow: the registry has to be real, so
                // `hasListener` cannot deny a listener the caller just added
                // and can still see in `removeListener`; and the silence has
                // to be said out loud once, because an event that accepts
                // listeners and never delivers is otherwise indistinguishable
                // from a Crest bug.
                const presenceOnlyEvent = (path) => {
                    const listeners = new Set();
                    let warned = false;
                    const warnOnce = () => {
                        if (warned) return;
                        warned = true;
                        try {
                            console.warn(
                                "Crest: browser." + path + " is registered "
                                + "for feature detection only. Crest cannot "
                                + "deliver this event, so no listener added "
                                + "to it will ever run."
                            );
                        } catch {}
                    };
                    return Object.freeze({
                        addListener(listener) {
                            if (typeof listener !== "function") return;
                            warnOnce();
                            listeners.add(listener);
                        },
                        removeListener(listener) {
                            listeners.delete(listener);
                        },
                        hasListener(listener) {
                            return listeners.has(listener);
                        },
                        hasListeners() { return listeners.size > 0; }
                    });
                };
                // Chrome answers a call either way, never both: supplying a
                // callback opts out of the promise entirely.
                const callbackOrPromise = (args, value) => {
                    const callback = args.at(-1);
                    if (typeof callback === "function") {
                        queueMicrotask(() => callback(value));
                        return undefined;
                    }
                    return Promise.resolve(value);
                };
                const rejectCallbackOrPromise = (args, message) => {
                    const callback = args.at(-1);
                    if (typeof callback === "function") {
                        queueMicrotask(
                            () => invokeCallbackWithLastError(
                                callback,
                                message
                            )
                        );
                        return undefined;
                    }
                    return Promise.reject(new Error(message));
                };
                // The filler for a member `emulatedSurface` declares and
                // Crest does not implement. It is not a no-op: a no-op
                // reports success for work that never happened, which is how
                // an extension ends up waiting forever on a download it
                // believes it started. The member exists, so feature
                // detection and property access take the Chrome branch, and
                // then it fails the way an unavailable capability fails.
                //
                // The schema shape is read off the name, which is the same
                // convention every WebExtension schema uses: `onFoo` is an
                // event, an initial capital is an enum, anything else is a
                // method. Methods answer whichever form the caller used —
                // a rejected promise, or `runtime.lastError` plus a callback.
                const presenceOnlyMember = (path, name) => {
                    if (/^on[A-Z]/.test(name)) {
                        return presenceOnlyEvent(path);
                    }
                    if (/^[A-Z]/.test(name)) {
                        return Object.freeze({});
                    }
                    return (...args) => rejectCallbackOrPromise(
                        args,
                        path + " is not available in Crest."
                    );
                };
                // Authored menu URL patterns are forwarded whole. Filtering
                // out the ones WebKit cannot parse emptied the list whenever
                // every pattern was unsupported, and an empty pattern list
                // means "the extension authored no restriction" — so a menu
                // item scoped to one site became a menu item on every site.
                // Swift decides what an unparseable pattern matches, which is
                // nothing.
                const authoredMenuPatterns = (patterns) =>
                    Array.isArray(patterns)
                        ? patterns.map((pattern) => String(pattern))
                        : [];
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
                    if (!namespaceUsesCompatibility("contextMenus")) {
                        return nativeMenus;
                    }
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
                        const normalized =
                            properties && typeof properties === "object"
                                ? properties
                                : {};
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
                            documentUrlPatterns: authoredMenuPatterns(
                                authored.documentUrlPatterns
                            ),
                            targetUrlPatterns: authoredMenuPatterns(
                                authored.targetUrlPatterns
                            ),
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
                        if (!isPrivilegedExtensionContext || port) return;
                        const runtime = nativeRuntimeWithMethod(
                            "connectNative"
                        );
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
                const internallyGrantedPermissionNames = new Set();
                if (!requiredPermissionNames.has("nativeMessaging")) {
                    // Crest grants WebKit's native-messaging permission only
                    // so the compatibility layer can reach private lifecycle
                    // and capability brokers. That host-owned transport must
                    // not appear as an extension-authored permission: password
                    // managers otherwise enable their optional desktop-app
                    // integration and retry a native host the user never
                    // granted.
                    internallyGrantedPermissionNames.add("nativeMessaging");
                }
                const permissionRequestContainsInternalAccess = (request) =>
                    Boolean(
                        request
                        && Array.isArray(request.permissions)
                        && request.permissions.some((permission) =>
                            internallyGrantedPermissionNames.has(permission)
                        )
                    );
                const partitionPermissionRequest = (request) => {
                    if (!request || typeof request !== "object") {
                        return {
                            emulated: [],
                            nativeRequest: request,
                            hasNativeAccess: false
                        };
                    }
                    const nativeRequest = {...request};
                    const emulated = [];
                    if (Array.isArray(request.permissions)) {
                        const nativePermissions = [];
                        for (const permission of request.permissions) {
                            if (compatibilityPermissionNames.has(permission)) {
                                emulated.push(permission);
                            } else {
                                nativePermissions.push(permission);
                            }
                        }
                        if (nativePermissions.length > 0) {
                            nativeRequest.permissions = nativePermissions;
                        } else {
                            delete nativeRequest.permissions;
                        }
                    }
                    const hasNativeAccess = (
                        Array.isArray(nativeRequest.permissions)
                        && nativeRequest.permissions.length > 0
                    ) || (
                        Array.isArray(nativeRequest.origins)
                        && nativeRequest.origins.length > 0
                    );
                    return {emulated, nativeRequest, hasNativeAccess};
                };
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
                    request,
                    failure
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
                    // follow-up against state it never confirmed. The bound is
                    // Crest's invention rather than an answer, so a
                    // callback-form caller is told through runtime.lastError
                    // that `false` here means "unanswered", not "not granted".
                    const timeout = globalThis.setTimeout(
                        () => {
                            if (failure) {
                                failure.message =
                                    "WebKit did not answer this permissions query in time.";
                            }
                            settle(false);
                        },
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
                const permissionCallbackOrPromise = (
                    args,
                    operation,
                    failure
                ) => {
                    const callback = args.at(-1);
                    if (typeof callback === "function") {
                        operation.then(
                            (value) => {
                                if (failure?.message) {
                                    invokeCallbackWithLastError(
                                        callback,
                                        failure.message,
                                        value
                                    );
                                    return;
                                }
                                callback(value);
                            },
                            (error) => invokeCallbackWithLastError(
                                callback,
                                error?.message
                                    ?? "Crest could not complete this permissions request.",
                                false
                            )
                        );
                        return undefined;
                    }
                    return operation;
                };
                const normalizedPermissionNamespaces = new WeakMap();
                const normalizePermissionsNamespace = (nativePermissions) => {
                    if (!namespaceUsesCompatibility("permissions")) {
                        return nativePermissions;
                    }
                    if (!nativePermissions) return nativePermissions;
                    if (normalizedPermissionNamespaces.has(nativePermissions)) {
                        return normalizedPermissionNamespaces.get(
                            nativePermissions
                        );
                    }

                    let nativeContains;
                    let nativeGetAll;
                    let nativeRemove;
                    try {
                        nativeContains = nativePermissions.contains;
                        nativeGetAll = nativePermissions.getAll;
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

                    const containsOperation = (request, failure) => {
                        if (permissionRequestContainsInternalAccess(request)) {
                            return Promise.resolve(false);
                        }
                        const partition = partitionPermissionRequest(request);
                        if (partition.emulated.some((permission) =>
                            !requiredPermissionNames.has(permission)
                        )) {
                            return Promise.resolve(false);
                        }
                        if (!partition.hasNativeAccess) {
                            return Promise.resolve(true);
                        }
                        return nativePermissionBoolean(
                            nativePermissions,
                            nativeContains,
                            partition.nativeRequest,
                            failure
                        );
                    };
                    const contains = (...args) => {
                        const failure = {};
                        return permissionCallbackOrPromise(
                            args,
                            containsOperation(args[0], failure),
                            failure
                        );
                    };
                    const getAllOperation = (failure) => new Promise((resolve) => {
                        let settled = false;
                        const settle = (value) => {
                            if (settled) return;
                            settled = true;
                            globalThis.clearTimeout(timeout);
                            const result = value && typeof value === "object"
                                ? {...value}
                                : {};
                            result.permissions = Array.isArray(
                                result.permissions
                            )
                                ? result.permissions.filter((permission) =>
                                    !internallyGrantedPermissionNames.has(
                                        permission
                                    )
                                )
                                : [];
                            if (!Array.isArray(result.origins)) {
                                result.origins = [];
                            }
                            resolve(result);
                        };
                        const timeout = globalThis.setTimeout(
                            () => {
                                if (failure) {
                                    failure.message =
                                        "WebKit did not answer permissions.getAll in time.";
                                }
                                settle({permissions: [], origins: []});
                            },
                            250
                        );
                        if (typeof nativeGetAll !== "function") {
                            settle({permissions: [], origins: []});
                            return;
                        }
                        let returned;
                        try {
                            returned = Reflect.apply(
                                nativeGetAll,
                                nativePermissions,
                                [(value) => settle(value)]
                            );
                        } catch {
                            settle({permissions: [], origins: []});
                            return;
                        }
                        if (returned?.then instanceof Function) {
                            returned.then(
                                (value) => settle(value),
                                () => settle({permissions: [], origins: []})
                            );
                        } else if (returned !== undefined) {
                            settle(returned);
                        }
                    });
                    const getAll = (...args) => {
                        const failure = {};
                        return permissionCallbackOrPromise(
                            args,
                            getAllOperation(failure),
                            failure
                        );
                    };
                    const remove = (...args) => {
                        const request = args[0];
                        const failure = {};
                        const operation = permissionRequestRemovesRequiredAccess(
                            request
                        )
                            ? Promise.resolve(false)
                            : containsOperation(request, failure).then(
                                (isGranted) => {
                                    if (!isGranted) return false;
                                    return nativePermissionBoolean(
                                        nativePermissions,
                                        nativeRemove,
                                        request,
                                        failure
                                    );
                                }
                            );
                        return permissionCallbackOrPromise(
                            args,
                            operation,
                            failure
                        );
                    };
                    const overlays = new Map([
                        ["contains", contains],
                        ["remove", remove]
                    ]);
                    if (typeof nativeGetAll === "function") {
                        overlays.set("getAll", getAll);
                    }
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
                                    writable: true,
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
                    if (!isPrivilegedExtensionContext) {
                        return rejectCallbackOrPromise(
                            args,
                            `Crest's ${api} capability is unavailable in webpage content scripts.`
                        );
                    }
                    // Send a foreground capability request through the live
                    // native facade. WebKit can replace an extension runtime
                    // object after compatibility initialization when a newly
                    // authorized API becomes available, so an early captured
                    // root is not authoritative here.
                    const runtime = nativeRuntimeWithMethod(
                        "sendNativeMessage"
                    );
                    const sendNativeMessage = runtime?.sendNativeMessage;
                    if (typeof sendNativeMessage !== "function") {
                        return rejectCallbackOrPromise(
                            args,
                            `Crest's ${api} capability is unavailable.`
                        );
                    }

                    const request = { api, ...payload };
                    // Broker traffic is invisible to the page's own console, so
                    // console capture also records each capability call and
                    // how it settled. This is what shows whether an extension
                    // asked Crest for something and what Crest answered.
                    const traceCapability = (suffix, detail) => {
                        if (!capturesExtensionConsole) return;
                        try {
                            reportRuntimeTrace(`capability.${api}${suffix}`, {
                                context: executionProcess,
                                ...detail
                            });
                        } catch {}
                    };
                    traceCapability("", { request: payload });
                    const response = new Promise((resolve, reject) => {
                        let settled = false;
                        const settle = (operation, value) => {
                            if (settled) return;
                            settled = true;
                            if (operation === reject) {
                                traceCapability(".rejected", {
                                    message: String(value?.message ?? value)
                                });
                            } else {
                                traceCapability(".resolved", { response: value });
                            }
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
                            (error) => invokeCallbackWithLastError(
                                callback,
                                error?.message
                                    ?? `Crest's ${api} capability failed.`
                            )
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
                let activeOffscreenDocumentURL;
                const serviceWorkerClients = Object.freeze({
                    async matchAll() {
                        // Chrome's WorkerGlobalScope.clients returns structured
                        // WindowClient handles. WebKit does not provide that
                        // API here, and chrome.extension.getViews() instead
                        // exposes live cross-context DOMWindow wrappers. Those
                        // wrappers become stale as a popup reloads and can crash
                        // WebKit when worker code reads location or document.
                        // Crest owns emulated offscreen documents and can expose
                        // their stable URL without handing the worker a live DOM
                        // wrapper. This preserves the pre-runtime.getContexts
                        // lifecycle check used by Chrome extensions while every
                        // other unrepresentable client remains conservatively
                        // absent.
                        if (activeOffscreenDocumentURL) {
                            try {
                                const hasDocument = await requestCapability(
                                    "offscreen.hasDocument",
                                    {},
                                    [],
                                    (response) =>
                                        response?.hasDocument === true
                                );
                                if (hasDocument) {
                                    return [Object.freeze({
                                        url: activeOffscreenDocumentURL
                                    })];
                                }
                            } catch {}
                        }
                        return [];
                    }
                });
                if (!globalThis.clients) {
                    try {
                        Object.defineProperty(globalThis, "clients", {
                            value: serviceWorkerClients,
                            writable: true,
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

                // A capability watch is the only long-lived native connection
                // this runtime opens, and the broker drops it immediately when
                // the package never requested the matching permission. A fixed
                // one-second retry therefore reconnected forever against a
                // refusal that will never change. Back off, and stop asking.
                const capabilityWatch = ({
                    api,
                    hasListeners,
                    onMessage,
                    subscription
                }) => {
                    const initialRetryDelay = 1000;
                    const maximumRetryDelay = 60000;
                    const maximumFailures = 6;
                    let port;
                    let reconnectHandle;
                    let failures = 0;
                    let abandoned = false;
                    let hadListeners = false;
                    const clearReconnect = () => {
                        globalThis.clearTimeout(reconnectHandle);
                        reconnectHandle = undefined;
                    };
                    // Abandonment must not outlive the reason for it.
                    //
                    // The broker refuses a watch the package has no permission
                    // for, and an OPTIONAL permission is exposed before it is
                    // granted: six refusals during that window used to retire
                    // the watch for the life of the context, so the grant the
                    // user then gave never delivered a single event. A fresh
                    // `addListener` — the listener count rising from zero — is
                    // a new statement of intent and the moment the answer can
                    // have changed, so it restores the budget.
                    //
                    // Merely obtaining a port does not: `connectNative`
                    // returns one synchronously and the broker disconnects it
                    // afterwards when it refuses, so resetting there would
                    // reconnect forever against a permanent no. What proves
                    // the watch works is a delivered message, which resets
                    // below.
                    const observeListeners = () => {
                        const listening = hasListeners();
                        if (listening && !hadListeners) {
                            abandoned = false;
                            failures = 0;
                        }
                        hadListeners = listening;
                        return listening;
                    };
                    const scheduleReconnect = () => {
                        if (abandoned) return;
                        failures += 1;
                        clearReconnect();
                        if (failures >= maximumFailures) {
                            abandoned = true;
                            try {
                                console.warn(
                                    `Crest stopped reconnecting the ${api} watch after ${maximumFailures} consecutive failures. Events for that API will not arrive in this context.`
                                );
                            } catch {}
                            return;
                        }
                        reconnectHandle = globalThis.setTimeout(
                            connect,
                            Math.min(
                                maximumRetryDelay,
                                initialRetryDelay * (2 ** (failures - 1))
                            )
                        );
                    };
                    const resubscribe = () => {
                        if (!port) return;
                        try {
                            port.postMessage(subscription());
                        } catch {}
                    };
                    const connect = () => {
                        const listening = observeListeners();
                        if (
                            abandoned
                            || !isPrivilegedExtensionContext
                            || port
                            || !listening
                        ) {
                            return;
                        }
                        const runtime = nativeRuntimeWithMethod(
                            "connectNative"
                        );
                        const connectNative = runtime?.connectNative;
                        if (typeof connectNative !== "function") return;
                        let connected;
                        try {
                            connected = Reflect.apply(
                                connectNative,
                                runtime,
                                [capabilityBrokerHost]
                            );
                        } catch {
                            connected = undefined;
                        }
                        if (!connected) {
                            scheduleReconnect();
                            return;
                        }
                        port = connected;
                        port.onMessage?.addListener((message) => {
                            // A delivered event proves the watch works, so the
                            // next disconnect starts a fresh budget.
                            failures = 0;
                            onMessage(message);
                        });
                        port.onDisconnect?.addListener(() => {
                            port = undefined;
                            if (!hasListeners()) return;
                            scheduleReconnect();
                        });
                        resubscribe();
                    };
                    const disconnect = () => {
                        clearReconnect();
                        const current = port;
                        port = undefined;
                        // An explicit teardown ends the episode the failures
                        // were counted against; whatever reconnects next
                        // starts from zero.
                        failures = 0;
                        abandoned = false;
                        hadListeners = false;
                        try { current?.disconnect(); } catch {}
                    };
                    return Object.freeze({
                        connect,
                        disconnect,
                        resubscribe
                    });
                };
                const notificationListeners = Object.freeze({
                    clicked: new Set(),
                    buttonClicked: new Set(),
                    closed: new Set()
                });
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
                const notificationWatch = capabilityWatch({
                    api: "notifications",
                    hasListeners: () => notificationListenerCount() > 0,
                    onMessage: publishNotificationEvent,
                    subscription: () => ({ api: "notifications.watch" })
                });
                const notificationEvent = (kind) => Object.freeze({
                    addListener(listener) {
                        if (typeof listener !== "function") return;
                        notificationListeners[kind].add(listener);
                        notificationWatch.connect();
                    },
                    removeListener(listener) {
                        notificationListeners[kind].delete(listener);
                        if (notificationListenerCount() > 0) return;
                        notificationWatch.disconnect();
                    },
                    hasListener(listener) {
                        return notificationListeners[kind].has(listener);
                    },
                    hasListeners() {
                        return notificationListeners[kind].size > 0;
                    }
                });
                // Crest presents extension notifications through the system
                // notification centre, which carries a title, a body, and
                // buttons and nothing else. Chrome's richer options are not
                // rejected — a notification the person can still act on beats
                // no notification — but dropping them without a word made an
                // extension's image, progress bar, or priority look delivered.
                const unsupportedNotificationOptions = Object.freeze([
                    "iconUrl",
                    "items",
                    "progress",
                    "imageUrl",
                    "requireInteraction",
                    "silent",
                    "priority",
                    "eventTime",
                    "contextMessage"
                ]);
                const warnedNotificationOptions = new Set();
                const warnUnsupportedNotificationOptions = (
                    method,
                    options
                ) => {
                    if (!options || typeof options !== "object") return;
                    const warnOnce = (key, description) => {
                        if (warnedNotificationOptions.has(key)) return;
                        warnedNotificationOptions.add(key);
                        try {
                            console.warn(
                                `notifications.${method}: Crest ignores ${description}.`
                            );
                        } catch {}
                    };
                    for (const key of unsupportedNotificationOptions) {
                        if (options[key] === undefined) continue;
                        warnOnce(key, `the "${key}" option`);
                    }
                    if (
                        options.type !== undefined
                        && options.type !== "basic"
                    ) {
                        warnOnce(
                            "type",
                            `the "${options.type}" notification type and presents a basic notification instead`
                        );
                    }
                };
                const notifications = Object.freeze({
                    onClicked: notificationEvent("clicked"),
                    onButtonClicked: notificationEvent("buttonClicked"),
                    onClosed: notificationEvent("closed"),
                    // `onPermissionLevelChanged` is supplied by the
                    // `emulatedSurface` filler, which hands back a
                    // `presenceOnlyEvent`. A `noopEvent` used to sit here and
                    // its `hasListener` denied listeners the caller had just
                    // added, so a package could not tell registration apart
                    // from a Crest bug.
                    create(...args) {
                        const hasIdentifier = typeof args[0] === "string";
                        const options = args[hasIdentifier ? 1 : 0] ?? {};
                        const notificationIdentifier = hasIdentifier
                            ? args[0]
                            : `crest-${Date.now()}-${Math.random()
                                .toString(36).slice(2)}`;
                        warnUnsupportedNotificationOptions("create", options);
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
                        warnUnsupportedNotificationOptions("update", options);
                        // Chrome's update is a partial edit: an omitted field
                        // keeps its current value. Send only the fields the
                        // caller supplied; the broker merges them over the
                        // notification it last posted. An explicit empty
                        // string is a legitimate value (an extension may blank
                        // a title), so only `undefined` means "keep".
                        const update = {
                            notificationIdentifier: String(args[0] ?? "")
                        };
                        if (options.title !== undefined) {
                            update.title = String(options.title);
                        }
                        if (options.message !== undefined) {
                            update.message = String(options.message);
                        }
                        if (Array.isArray(options.buttons)) {
                            update.buttonTitles = options.buttons.map(
                                (button) => String(button?.title ?? "")
                            );
                        }
                        return requestCapability(
                            "notifications.update",
                            update,
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
                const scripting = {
                    ExecutionWorld: Object.freeze({
                        ISOLATED: "ISOLATED",
                        MAIN: "MAIN"
                    })
                };
                const permissions = {};
                // WebKit does not expose the privacy namespace. Publish the
                // complete Chromium/Firefox group structure with conservative
                // platform values, and report every setting as uncontrollable.
                // Extensions can therefore inspect or restore a preference
                // without mistaking Crest for the owner of the real setting.
                const privacyNetwork = {
                    networkPredictionEnabled: uncontrollableSetting(true),
                    peerConnectionEnabled: uncontrollableSetting(true),
                    webRTCIPHandlingPolicy: uncontrollableSetting("default"),
                    tlsVersionRestriction: uncontrollableSetting({
                        minimum: "TLSv1.2",
                        maximum: "TLSv1.3"
                    }),
                    httpsOnlyMode: uncontrollableSetting("never"),
                    globalPrivacyControl: uncontrollableSetting(false)
                };
                const privacyServices = {
                    alternateErrorPagesEnabled: uncontrollableSetting(false),
                    autofillEnabled: uncontrollableSetting(false),
                    autofillCreditCardEnabled: uncontrollableSetting(false),
                    autofillAddressEnabled: uncontrollableSetting(false),
                    passwordSavingEnabled: uncontrollableSetting(true),
                    safeBrowsingEnabled: uncontrollableSetting(true),
                    safeBrowsingExtendedReportingEnabled:
                        uncontrollableSetting(false),
                    searchSuggestEnabled: uncontrollableSetting(true),
                    spellingServiceEnabled: uncontrollableSetting(false),
                    translationServiceEnabled: uncontrollableSetting(false)
                };
                const privacyWebsites = {
                    adMeasurementEnabled: uncontrollableSetting(false),
                    doNotTrackEnabled: uncontrollableSetting(false),
                    fledgeEnabled: uncontrollableSetting(false),
                    hyperlinkAuditingEnabled: uncontrollableSetting(true),
                    protectedContentEnabled: uncontrollableSetting(false),
                    referrersEnabled: uncontrollableSetting(true),
                    relatedWebsiteSetsEnabled: uncontrollableSetting(false),
                    thirdPartyCookiesAllowed: uncontrollableSetting(true),
                    topicsEnabled: uncontrollableSetting(false),
                    resistFingerprinting: uncontrollableSetting(false),
                    firstPartyIsolate: uncontrollableSetting(false),
                    trackingProtectionMode: uncontrollableSetting("never"),
                    cookieConfig: uncontrollableSetting({
                        behavior: "allow_all",
                        nonPersistentCookies: false
                    })
                };
                const storageManaged = {
                    onChanged: noopEvent,
                    get(...args) { return callbackOrPromise(args, {}); },
                    getBytesInUse(...args) {
                        return callbackOrPromise(args, 0);
                    }
                };
                const management = {
                    getSelf(...args) {
                        const manifest = primaryRoot.runtime.getManifest();
                        return callbackOrPromise(args, {
                            id: primaryRoot.runtime.id,
                            name: manifest.name,
                            version: manifest.version,
                            enabled: true,
                            type: "extension"
                        });
                    }
                };
                const downloads = {
                    download(...args) {
                        const options = args[0];
                        if (
                            !options
                            || typeof options !== "object"
                            || typeof options.url !== "string"
                            || options.url.length === 0
                        ) {
                            return rejectCallbackOrPromise(
                                args,
                                "downloads.download requires a URL."
                            );
                        }
                        return requestCapability(
                            "downloads.download",
                            {
                                url: options.url,
                                filename:
                                    typeof options.filename === "string"
                                        ? options.filename
                                        : undefined,
                                saveAs: options.saveAs === true
                            },
                            args,
                            (response) => {
                                const downloadID = response?.downloadID;
                                if (!Number.isSafeInteger(downloadID)) {
                                    throw new Error(
                                        "Crest returned an invalid download identifier."
                                    );
                                }
                                return downloadID;
                            }
                        );
                    }
                };
                const offscreenReasons = Object.freeze({
                    TESTING: "TESTING",
                    AUDIO_PLAYBACK: "AUDIO_PLAYBACK",
                    IFRAME_SCRIPTING: "IFRAME_SCRIPTING",
                    DOM_SCRAPING: "DOM_SCRAPING",
                    BLOBS: "BLOBS",
                    DOM_PARSER: "DOM_PARSER",
                    USER_MEDIA: "USER_MEDIA",
                    DISPLAY_MEDIA: "DISPLAY_MEDIA",
                    WEB_RTC: "WEB_RTC",
                    CLIPBOARD: "CLIPBOARD",
                    LOCAL_STORAGE: "LOCAL_STORAGE",
                    WORKERS: "WORKERS",
                    BATTERY_STATUS: "BATTERY_STATUS",
                    MATCH_MEDIA: "MATCH_MEDIA",
                    GEOLOCATION: "GEOLOCATION"
                });
                const offscreen = {
                    Reason: offscreenReasons,
                    createDocument(...args) {
                        const parameters = args[0];
                        if (
                            !parameters
                            || typeof parameters !== "object"
                            || typeof parameters.url !== "string"
                            || parameters.url.length === 0
                            || !Array.isArray(parameters.reasons)
                            || parameters.reasons.length === 0
                            || parameters.reasons.some(
                                (reason) => typeof reason !== "string"
                                    || reason.length === 0
                            )
                            || typeof parameters.justification !== "string"
                            || parameters.justification.trim().length === 0
                        ) {
                            return rejectCallbackOrPromise(
                                args,
                                "offscreen.createDocument requires a bundled URL, reasons, and justification."
                            );
                        }
                        const url = fallbackResourceURL(parameters.url);
                        return requestCapability(
                            "offscreen.createDocument",
                            {
                                url,
                                reasons: parameters.reasons,
                                justification: parameters.justification
                            },
                            args,
                            (response) => {
                                if (response?.created !== true) {
                                    throw new Error(
                                        "Crest did not create the offscreen document."
                                    );
                                }
                                activeOffscreenDocumentURL = url;
                            }
                        );
                    },
                    closeDocument(...args) {
                        return requestCapability(
                            "offscreen.closeDocument",
                            {},
                            args,
                            (response) => {
                                if (response?.closed !== true) {
                                    throw new Error(
                                        "Crest did not close the offscreen document."
                                    );
                                }
                                activeOffscreenDocumentURL = undefined;
                            }
                        );
                    },
                    hasDocument(...args) {
                        return requestCapability(
                            "offscreen.hasDocument",
                            {},
                            args,
                            (response) =>
                                response?.hasDocument === true
                        );
                    }
                };
                \(BrowserExtensionSidebarCompatibilityScript.source)
                \(BrowserExtensionTabGroupsCompatibilityScript.source)
                \(BrowserExtensionDebuggerCompatibilityScript.source)
                const idleStateChangeListeners = new Set();
                let idleDetectionIntervalInSeconds = 60;
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
                const idleWatch = capabilityWatch({
                    api: "idle",
                    hasListeners: () => idleStateChangeListeners.size > 0,
                    onMessage: publishIdleStateChange,
                    subscription: () => ({
                        api: "idle.watch",
                        detectionIntervalInSeconds:
                            idleDetectionIntervalInSeconds
                    })
                });
                const idleStateChangedEvent = Object.freeze({
                    addListener(listener) {
                        if (typeof listener !== "function") return;
                        idleStateChangeListeners.add(listener);
                        idleWatch.connect();
                    },
                    removeListener(listener) {
                        idleStateChangeListeners.delete(listener);
                        if (idleStateChangeListeners.size > 0) return;
                        idleWatch.disconnect();
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
                            idleWatch.connect();
                            idleWatch.resubscribe();
                        }
                    }
                };
                const webRequest = {
                    handlerBehaviorChanged(...args) {
                        return callbackOrPromise(args);
                    }
                };
                // WebKit 27 exposes the core navigation lifecycle and frame
                // query methods, but omits four events present in both the
                // Chromium and Firefox schemas. The matrix routes these
                // `presenceOnly`: registration is preserved, delivery is never
                // claimed. A `presenceOnly` route does not own its member, so
                // a future WebKit implementation replaces the placeholder
                // rather than being displaced by it.
                const webNavigation = Object.fromEntries(
                    eventMembersOf("webNavigation").map((member) => [
                        member,
                        presenceOnlyEvent(`webNavigation.${member}`)
                    ])
                );
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
                \(BrowserExtensionRuntimeContextsCompatibilityScript.source)
                \(BrowserExtensionDeclarativeNetRequestCompatibilityScript.source)
                // The routed fallback set does not depend on which root asks
                // for it — routes, processes, and declared permissions are
                // fixed for the life of this context. Computing it once means
                // `chrome.idle` and `browser.idle` are the SAME Crest object,
                // as they are one namespace in Chrome, and it lets a caller
                // recognize a namespace Crest has already installed by
                // identity instead of re-installing an equivalent copy over
                // references extensions may already hold.
                let routedFallbackCache;
                const fallbacksFor = (nativeRoot) => {
                    void nativeRoot;
                    if (routedFallbackCache) return routedFallbackCache;
                    const fallbacks = {
                        action,
                        browserAction: action,
                        declarativeNetRequest,
                        scripting,
                        permissions,
                        privacy: {
                            network: privacyNetwork,
                            services: privacyServices,
                            websites: privacyWebsites
                        },
                        storage: { managed: storageManaged },
                        notifications,
                        management,
                        downloads,
                        offscreen,
                        sidePanel,
                        sidebarAction,
                        tabGroups,
                        // `debugger` is a reserved word; the namespace object
                        // is bound to a legal identifier and published here
                        // under its schema name.
                        debugger: debuggerNamespace,
                        idle,
                        webNavigation,
                        webRequest,
                        runtime
                    };
                    const routedFallbacks = [];
                    for (const [namespace, fallback] of Object.entries(
                        fallbacks
                    )) {
                        if (!namespaceUsesCompatibility(namespace)) continue;
                        const members = Object.fromEntries(
                            Object.entries(fallback).filter(([member]) =>
                                memberUsesCompatibility(
                                    `${namespace}.${member}`
                                )
                            )
                        );
                        // Complete the namespace. An emulated namespace is
                        // published whole or not at all: what Crest
                        // implements above, plus an honest placeholder for
                        // every other member the reference schema defines.
                        // The implemented members were just filtered by
                        // route and process, and each filler is filtered the
                        // same way, so a member the matrix removes stays
                        // removed and a background-only member does not
                        // appear in a content script.
                        for (
                            const member of emulatedSurface[namespace] ?? []
                        ) {
                            if (member in members) continue;
                            const path = `${namespace}.${member}`;
                            if (!memberUsesCompatibility(path)) continue;
                            members[member] = presenceOnlyMember(path, member);
                        }
                        if (Object.keys(members).length > 0) {
                            routedFallbacks.push([namespace, members]);
                        }
                    }
                    routedFallbackCache = Object.fromEntries(routedFallbacks);
                    return routedFallbackCache;
                };
                // `pathPrefix` is the matrix path of `nativeValue` itself: the
                // empty string at an extension root, then the namespace, then
                // `namespace.member` as the walk descends. It is what lets the
                // route — not `existing === undefined` — decide the winner.
                //
                // Nothing installed here is pinned. Crest used to redefine
                // every surviving native property non-configurable, which
                // broke extensions that legitimately monkeypatch `chrome.*`;
                // Chrome's own API objects are writable and configurable, so
                // both the native properties Crest leaves alone and the ones
                // it installs stay that way.
                const installFallbacks = (
                    nativeValue,
                    fallbacks,
                    pathPrefix = ""
                ) => {
                    if (!nativeValue) return;

                    for (const [property, fallback] of Object.entries(fallbacks)) {
                        const path = pathPrefix
                            ? `${pathPrefix}.${property}`
                            : property;
                        let existing;
                        try { existing = nativeValue[property]; } catch { continue; }

                        if (existing === undefined || crestOwnsPath(path)) {
                            try {
                                Object.defineProperty(nativeValue, property, {
                                    value: fallback,
                                    writable: true,
                                    configurable: true,
                                    enumerable: true
                                });
                            } catch {
                                try { nativeValue[property] = fallback; } catch {}
                            }
                            continue;
                        }
                        if (
                            fallback
                            && typeof fallback === "object"
                            && (typeof existing === "object"
                                || typeof existing === "function")
                        ) {
                            installFallbacks(existing, fallback, path);
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
                                writable: true,
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
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot[property] = normalizedMenus;
                            } catch {}
                        }
                    }
                    let nativeWebRequest;
                    try { nativeWebRequest = nativeRoot.webRequest; } catch {}
                    const normalizedWebRequest =
                        normalizeWebRequestNamespace(nativeWebRequest);
                    if (
                        normalizedWebRequest
                        && normalizedWebRequest !== nativeWebRequest
                    ) {
                        try {
                            Object.defineProperty(nativeRoot, "webRequest", {
                                value: normalizedWebRequest,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot.webRequest = normalizedWebRequest;
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
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot.permissions = normalizedPermissions;
                            } catch {}
                        }
                    }
                    let nativeWindows;
                    try { nativeWindows = nativeRoot.windows; } catch {}
                    const normalizedWindows =
                        normalizeWindowsNamespace(nativeWindows);
                    if (
                        normalizedWindows
                        && normalizedWindows !== nativeWindows
                    ) {
                        try {
                            Object.defineProperty(nativeRoot, "windows", {
                                value: normalizedWindows,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try { nativeRoot.windows = normalizedWindows; } catch {}
                        }
                    }
                    let nativeExtension;
                    try { nativeExtension = nativeRoot.extension; } catch {}
                    const normalizedExtension =
                        normalizeExtensionNamespace(nativeExtension);
                    if (
                        normalizedExtension
                        && normalizedExtension !== nativeExtension
                    ) {
                        try {
                            Object.defineProperty(nativeRoot, "extension", {
                                value: normalizedExtension,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot.extension = normalizedExtension;
                            } catch {}
                        }
                    }
                    let nativeAlarms;
                    try { nativeAlarms = nativeRoot.alarms; } catch {}
                    const normalizedAlarms =
                        normalizeAlarmsNamespace(nativeAlarms);
                    if (
                        normalizedAlarms
                        && normalizedAlarms !== nativeAlarms
                    ) {
                        try {
                            Object.defineProperty(nativeRoot, "alarms", {
                                value: normalizedAlarms,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot.alarms = normalizedAlarms;
                            } catch {}
                        }
                    }
                    let nativeStorage;
                    try { nativeStorage = nativeRoot.storage; } catch {}
                    const normalizedStorage =
                        normalizeStorageNamespace(nativeStorage);
                    if (
                        normalizedStorage
                        && normalizedStorage !== nativeStorage
                    ) {
                        try {
                            Object.defineProperty(nativeRoot, "storage", {
                                value: normalizedStorage,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try {
                                nativeRoot.storage = normalizedStorage;
                            } catch {}
                        }
                    }
                    const { runtime: runtimeFallback, ...fallbacks } =
                        fallbacksFor(nativeRoot);
                    installFallbacks(nativeRoot, fallbacks);
                    installFallbacks(
                        nativeRoot.runtime,
                        runtimeFallback,
                        "runtime"
                    );
                    if (nativeRoot.runtime) {
                        // The prepared manifest can contain host-owned grants
                        // and bootstrap resources that were not authored by
                        // the extension. Exposing those changes makes packages
                        // enable code paths the user never granted (notably a
                        // native companion retry loop). Override only the
                        // method on WebKit's native runtime object: replacing
                        // that object breaks WebKit's event and Port routing.
                        let descriptor;
                        try {
                            descriptor = Reflect.getOwnPropertyDescriptor(
                                nativeRoot.runtime,
                                "getManifest"
                            );
                        } catch {}
                        try {
                            Object.defineProperty(
                                nativeRoot.runtime,
                                "getManifest",
                                {
                                    value: () => declaredManifest,
                                    writable: true,
                                    configurable: true,
                                    enumerable: descriptor?.enumerable ?? true
                                }
                            );
                        } catch {
                            try {
                                nativeRoot.runtime.getManifest = () =>
                                    declaredManifest;
                            } catch {}
                        }
                    }
                    return nativeRoot;
                };
                const namespaceFacade = (
                    nativeValue,
                    fallback,
                    explicitOverlays = new Map(),
                    hiddenProperties = new Set()
                ) => {
                    if (nativeValue === undefined || nativeValue === null) {
                        return fallback;
                    }
                    if (
                        (!fallback
                            || typeof fallback !== "object"
                            || Object.keys(fallback).length === 0)
                        && explicitOverlays.size === 0
                        && hiddenProperties.size === 0
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
                    // WebKit exposes extension namespaces as exotic objects.
                    // Re-entering their membership/descriptor hooks from a
                    // facade Proxy can cause capability-enumeration libraries
                    // to spin forever in WebKit's microtask queue. Namespace
                    // capabilities are static for the life of an extension
                    // context, so snapshot both that surface and its values
                    // once and keep ordinary Proxy access and reflection
                    // entirely in JavaScript afterwards.
                    const nativePropertyKeys = new Set();
                    const nativeEnumerableProperties = new Map();
                    const nativePropertyValues = new Map();
                    try {
                        for (const property of Reflect.ownKeys(nativeValue)) {
                            if (hiddenProperties.has(property)) continue;
                            nativePropertyKeys.add(property);
                            let descriptor;
                            try {
                                descriptor = Reflect.getOwnPropertyDescriptor(
                                    nativeValue,
                                    property
                                );
                            } catch {}
                            nativeEnumerableProperties.set(
                                property,
                                descriptor?.enumerable ?? true
                            );
                            let value;
                            try {
                                value = Reflect.get(
                                    nativeValue,
                                    property,
                                    nativeValue
                                );
                            } catch {}
                            nativePropertyValues.set(property, value);
                        }
                    } catch {}
                    for (const property of fallbackValues.keys()) {
                        if (nativePropertyValues.has(property)) continue;
                        let value;
                        try {
                            value = Reflect.get(
                                nativeValue,
                                property,
                                nativeValue
                            );
                        } catch {}
                        nativePropertyValues.set(property, value);
                        if (value !== undefined) {
                            nativePropertyKeys.add(property);
                            nativeEnumerableProperties.set(property, true);
                        }
                    }
                    const boundMethods = new Map();
                    const nestedFacades = new Map();
                    const nativePropertyValue = (property) => {
                        if (hiddenProperties.has(property)) return undefined;
                        if (nativePropertyValues.has(property)) {
                            return nativePropertyValues.get(property);
                        }
                        // Some WebKit namespaces expose native methods through
                        // an inherited/exotic lookup without reporting them
                        // from `ownKeys`. Resolve an otherwise unknown direct
                        // access once, then keep all later access in JavaScript
                        // so capability probes cannot re-enter WebKit forever.
                        let value;
                        try {
                            value = Reflect.get(
                                nativeValue,
                                property,
                                nativeValue
                            );
                        } catch {}
                        nativePropertyValues.set(property, value);
                        if (value !== undefined) {
                            nativePropertyKeys.add(property);
                            nativeEnumerableProperties.set(property, true);
                        }
                        return value;
                    };
                    const resolvedValue = (property) => {
                        if (hiddenProperties.has(property)) return undefined;
                        if (explicitOverlays.has(property)) {
                            return explicitOverlays.get(property);
                        }
                        const value = nativePropertyValue(property);
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
                            if (hiddenProperties.has(property)) return false;
                            try {
                                const didSet = Reflect.set(
                                    nativeValue,
                                    property,
                                    value,
                                    nativeValue
                                );
                                if (didSet) {
                                    nativePropertyKeys.add(property);
                                    nativePropertyValues.set(property, value);
                                    nativeEnumerableProperties.set(
                                        property,
                                        true
                                    );
                                }
                                return didSet;
                            } catch {
                                return false;
                            }
                        },
                        has(_, property) {
                            if (hiddenProperties.has(property)) return false;
                            if (
                                explicitOverlays.has(property)
                                || fallbackValues.has(property)
                                || nativePropertyKeys.has(property)
                            ) {
                                return true;
                            }
                            return nativePropertyValue(property) !== undefined;
                        },
                        ownKeys() {
                            const keys = new Set(nativePropertyKeys);
                            for (const property of fallbackValues.keys()) {
                                keys.add(property);
                            }
                            for (const property of explicitOverlays.keys()) {
                                keys.add(property);
                            }
                            for (const property of hiddenProperties) {
                                keys.delete(property);
                            }
                            return Array.from(keys);
                        },
                        getOwnPropertyDescriptor(_, property) {
                            if (hiddenProperties.has(property)) {
                                return undefined;
                            }
                            if (!explicitOverlays.has(property)
                                && !fallbackValues.has(property)
                                && !nativePropertyKeys.has(property)) {
                                return undefined;
                            }
                            return {
                                value: resolvedValue(property),
                                writable: true,
                                configurable: true,
                                enumerable:
                                    nativeEnumerableProperties.get(property)
                                    ?? true
                            };
                        }
                    });
                };
                const normalizedExtensionNamespaces = new WeakMap();
                const normalizeExtensionNamespace = (nativeExtension) => {
                    if (
                        !namespaceUsesCompatibility("extension")
                        || !nativeExtension
                        || !hasMV3ServiceWorker
                        || !isBackgroundWorker
                    ) {
                        return nativeExtension;
                    }
                    if (
                        normalizedExtensionNamespaces.has(nativeExtension)
                    ) {
                        return normalizedExtensionNamespaces.get(
                            nativeExtension
                        );
                    }

                    // Chrome exposes these DOM-window APIs only to foreground
                    // extension pages. WebKit currently exposes them inside an
                    // MV3 worker too, where their cross-context Window wrappers
                    // can outlive a popup and crash during reload/teardown.
                    // Preserve the rest of the native extension namespace but
                    // make the worker capability surface match Chrome exactly.
                    // The list is the matrix's, not a literal: a background
                    // *document* keeps these members, so the axis is the
                    // background environment and the guards above are what
                    // restrict this to an MV3 worker.
                    const foregroundOnlyMethods =
                        backgroundWorkerHiddenMembersOf("extension");
                    if (foregroundOnlyMethods.size === 0) {
                        normalizedExtensionNamespaces.set(
                            nativeExtension,
                            nativeExtension
                        );
                        return nativeExtension;
                    }
                    const normalized = namespaceFacade(
                        nativeExtension,
                        {},
                        new Map(),
                        foregroundOnlyMethods
                    );
                    normalizedExtensionNamespaces.set(
                        nativeExtension,
                        normalized
                    );
                    normalizedExtensionNamespaces.set(normalized, normalized);
                    return normalized;
                };
                const normalizedWorkerRuntimeNamespaces = new WeakMap();
                const normalizeWorkerRuntimeNamespace = (nativeRuntime) => {
                    if (
                        !namespaceUsesCompatibility("runtime")
                        || !nativeRuntime
                        || !hasMV3ServiceWorker
                        || !isBackgroundWorker
                    ) {
                        return nativeRuntime;
                    }
                    if (
                        normalizedWorkerRuntimeNamespaces.has(nativeRuntime)
                    ) {
                        return normalizedWorkerRuntimeNamespaces.get(
                            nativeRuntime
                        );
                    }

                    // runtime.getBackgroundPage is the callback-form sibling
                    // of extension.getBackgroundPage and likewise returns a
                    // live Window. Chrome does not expose it to MV3 workers;
                    // keep it outside the worker boundary while preserving the
                    // native runtime object as every bound method's receiver.
                    // The matrix names the member, next to the sibling it
                    // shares a hazard with.
                    const workerHiddenRuntimeMembers =
                        backgroundWorkerHiddenMembersOf("runtime");
                    if (workerHiddenRuntimeMembers.size === 0) {
                        normalizedWorkerRuntimeNamespaces.set(
                            nativeRuntime,
                            nativeRuntime
                        );
                        return nativeRuntime;
                    }
                    const normalized = namespaceFacade(
                        nativeRuntime,
                        {},
                        new Map(),
                        workerHiddenRuntimeMembers
                    );
                    normalizedWorkerRuntimeNamespaces.set(
                        nativeRuntime,
                        normalized
                    );
                    normalizedWorkerRuntimeNamespaces.set(
                        normalized,
                        normalized
                    );
                    return normalized;
                };
                // WebKit exposes separate `chrome` and `browser` facade
                // objects for the same extension global. Alarm listeners are
                // one logical event in Chrome, so normalize both facades onto
                // one listener set and one transport rather than registering a
                // second native listener while visiting the alternate root.
                const normalizedAlarmNamespaces = new WeakMap();
                const alarmListeners = new Set();
                const alarmBridgeMarker =
                    "__crestWebExtensionAlarmBridgeV1";
                let alarmBridge;
                let alarmBridgeUnavailable = false;
                let nativeAlarmBridgeInstalled = false;
                const dispatchAlarm = (alarm) => {
                    for (const listener of Array.from(alarmListeners)) {
                        try { listener(alarm); } catch {}
                    }
                };
                const virtualOnAlarm = Object.freeze({
                    addListener(listener) {
                        if (typeof listener === "function") {
                            alarmListeners.add(listener);
                        }
                    },
                    removeListener(listener) {
                        alarmListeners.delete(listener);
                    },
                    hasListener(listener) {
                        return alarmListeners.has(listener);
                    },
                    hasListeners() {
                        return alarmListeners.size > 0;
                    }
                });
                const installAlarmBroadcastBridge = () => {
                    if (alarmBridge) return true;
                    if (alarmBridgeUnavailable) return false;
                    try {
                        alarmBridge = new BroadcastChannel(
                            alarmBridgeMarker
                        );
                    } catch {
                        // Without a transport a virtual event can never be
                        // fed. Report the failure so the caller keeps native
                        // alarm delivery instead of installing a silent event.
                        alarmBridge = undefined;
                        alarmBridgeUnavailable = true;
                        return false;
                    }
                    try {
                        if (!isBackgroundWorker) {
                            alarmBridge.addEventListener(
                                "message",
                                (event) => {
                                    const payload = event.data
                                        ?.[alarmBridgeMarker];
                                    if (
                                        payload?.version !== 1
                                        || payload.kind !== "alarm-fired"
                                        || !payload.alarm
                                        || typeof payload.alarm !== "object"
                                    ) {
                                        return;
                                    }
                                    dispatchAlarm(payload.alarm);
                                }
                            );
                            globalThis.addEventListener?.(
                                "pagehide",
                                () => {
                                    try { alarmBridge?.close(); } catch {}
                                    alarmBridge = undefined;
                                },
                                { once: true }
                            );
                        }
                    } catch {}
                    return true;
                };
                const normalizeAlarmsNamespace = (nativeAlarms) => {
                    if (
                        !namespaceUsesCompatibility("alarms")
                        || !nativeAlarms
                        || backgroundEnvironment !== "worker"
                    ) {
                        // Only a worker background owns alarms durably. When
                        // preparation collapsed a dual-environment package to
                        // a background document, that document is the alarm
                        // owner and must keep native onAlarm: nothing would
                        // ever feed a virtual event in its place.
                        return nativeAlarms;
                    }
                    if (normalizedAlarmNamespaces.has(nativeAlarms)) {
                        return normalizedAlarmNamespaces.get(nativeAlarms);
                    }

                    let nativeOnAlarm;
                    let nativeAddListener;
                    try {
                        nativeOnAlarm = nativeAlarms.onAlarm;
                        nativeAddListener = nativeOnAlarm?.addListener;
                    } catch {}
                    if (
                        !nativeOnAlarm
                        || typeof nativeAddListener !== "function"
                    ) {
                        normalizedAlarmNamespaces.set(
                            nativeAlarms,
                            nativeAlarms
                        );
                        return nativeAlarms;
                    }

                    // WebKit 27 can retain an extension page's event namespace
                    // after its DOMWindow has been destroyed. A later native
                    // alarm dispatch then invokes that stale page listener and
                    // crashes in JSDOMWindow::getOwnPropertySlot. Chrome's MV3
                    // contract already makes the service worker the durable
                    // alarm owner, so keep exactly one native listener there
                    // and fan the event out to live page contexts in JavaScript.
                    // Native create/get/clear methods remain untouched, which
                    // preserves WebKit's persistence, clamping, and worker wake.
                    if (!installAlarmBroadcastBridge()) {
                        // No BroadcastChannel means no feeder for a virtual
                        // event. Native delivery is the only path left.
                        normalizedAlarmNamespaces.set(
                            nativeAlarms,
                            nativeAlarms
                        );
                        return nativeAlarms;
                    }
                    if (isBackgroundWorker && !nativeAlarmBridgeInstalled) {
                        const receiveNativeAlarm = (alarm) => {
                            dispatchAlarm(alarm);
                            try {
                                alarmBridge?.postMessage({
                                    [alarmBridgeMarker]: {
                                        version: 1,
                                        kind: "alarm-fired",
                                        alarm
                                    }
                                });
                            } catch {}
                        };
                        try {
                            Reflect.apply(
                                nativeAddListener,
                                nativeOnAlarm,
                                [receiveNativeAlarm]
                            );
                            nativeAlarmBridgeInstalled = true;
                        } catch {}
                        if (!nativeAlarmBridgeInstalled) {
                            // The worker owns native delivery. Without it the
                            // virtual event has no source at all, so keep the
                            // native event rather than a silent addListener.
                            normalizedAlarmNamespaces.set(
                                nativeAlarms,
                                nativeAlarms
                            );
                            return nativeAlarms;
                        }
                    }

                    // Do not patch WebKit's exotic event object in place.
                    // It can report the JavaScript methods back during this
                    // bootstrap and silently restore its native methods once
                    // the script returns. That leaves real extension pages
                    // registered with native alarm dispatch even though a
                    // plain-object fixture appears normalized. Always expose
                    // the virtual event through an ordinary namespace facade
                    // instead, while every scheduling/query method continues
                    // to bind to the native alarms namespace.
                    const normalized = namespaceFacade(
                        nativeAlarms,
                        {},
                        new Map([["onAlarm", virtualOnAlarm]])
                    );
                    normalizedAlarmNamespaces.set(nativeAlarms, normalized);
                    normalizedAlarmNamespaces.set(normalized, normalized);
                    return normalized;
                };
                const unsupportedWindowUpdateProperties = new Set([
                    "top",
                    "left",
                    "width",
                    "height"
                ]);
                const normalizedWindowNamespaces = new WeakMap();
                const normalizeWindowsNamespace = (nativeWindows) => {
                    if (!namespaceUsesCompatibility("windows")) {
                        return nativeWindows;
                    }
                    if (!nativeWindows) return nativeWindows;
                    if (normalizedWindowNamespaces.has(nativeWindows)) {
                        return normalizedWindowNamespaces.get(nativeWindows);
                    }

                    let nativeCreate;
                    let nativeUpdate;
                    try { nativeCreate = nativeWindows.create; } catch {}
                    try { nativeUpdate = nativeWindows.update; } catch {}
                    if (
                        typeof nativeCreate !== "function"
                        && typeof nativeUpdate !== "function"
                    ) {
                        normalizedWindowNamespaces.set(
                            nativeWindows,
                            nativeWindows
                        );
                        return nativeWindows;
                    }

                    const isNativeWindow = (value) => Boolean(
                        value
                        && typeof value === "object"
                        && value.id !== undefined
                        && value.id !== null
                    );
                    const invokeNativeWindow = (
                        method,
                        args,
                        completion,
                        fallbackDelay
                    ) => {
                        let completed = false;
                        let fallback;
                        const finish = (value, error) => {
                            if (completed) return;
                            completed = true;
                            if (fallback !== undefined) clearTimeout(fallback);
                            completion(value, error);
                        };
                        const callback = (value) => {
                            let lastError;
                            try { lastError = nativeRuntime?.lastError; } catch {}
                            finish(value, lastError);
                        };
                        let returned;
                        try {
                            returned = Reflect.apply(
                                method,
                                nativeWindows,
                                [...args, callback]
                            );
                        } catch (error) {
                            finish(undefined, error);
                            return;
                        }
                        if (returned?.then instanceof Function) {
                            returned.then(
                                (value) => finish(value, undefined),
                                (error) => finish(undefined, error)
                            );
                            return;
                        }
                        if (returned !== undefined) {
                            finish(returned, undefined);
                            return;
                        }
                        fallback = setTimeout(
                            () => finish(undefined, undefined),
                            fallbackDelay
                        );
                    };
                    const nativeWindowCall = (methodName, args = []) =>
                        new Promise((resolve, reject) => {
                            let method;
                            try { method = nativeWindows[methodName]; } catch {}
                            if (typeof method !== "function") {
                                reject(new Error(
                                    `WebKit does not expose windows.${methodName}.`
                                ));
                                return;
                            }
                            invokeNativeWindow(
                                method,
                                args,
                                (value, error) => {
                                    if (error) {
                                        reject(
                                            error instanceof Error
                                                ? error
                                                : new Error(
                                                    error?.message
                                                        ?? String(error)
                                                )
                                        );
                                        return;
                                    }
                                    resolve(value);
                                },
                                1000
                            );
                        });
                    const brokeredPopupWindow = async (requested) => {
                        const response = await requestCapability(
                            "windows.create",
                            { createData: requested },
                            []
                        );
                        if (response?.presented !== true) {
                            throw new Error(
                                "Crest did not present the extension window."
                            );
                        }

                        if (requested.focused !== false) {
                            try {
                                const focused = await nativeWindowCall(
                                    "getLastFocused",
                                    [{
                                        populate: true,
                                        windowTypes: ["popup"]
                                    }]
                                );
                                if (isNativeWindow(focused)) return focused;
                            } catch {}
                        }
                        const windows = await nativeWindowCall(
                            "getAll",
                            [{ populate: true, windowTypes: ["popup"] }]
                        );
                        const popup = Array.isArray(windows)
                            ? Array.from(windows).reverse().find((window) =>
                                isNativeWindow(window)
                                && (
                                    window.type === undefined
                                    || window.type === "popup"
                                )
                            )
                            : undefined;
                        if (!popup) {
                            throw new Error(
                                "WebKit did not publish the presented extension window."
                            );
                        }
                        return popup;
                    };
                    const create = (...inputArguments) => {
                        const args = Array.from(inputArguments);
                        const callback = typeof args.at(-1) === "function"
                            ? args.pop()
                            : undefined;
                        const requested = args[0]
                            && typeof args[0] === "object"
                            ? args[0]
                            : {};
                        const requestedURLs = Array.isArray(requested.url)
                            ? requested.url
                            : [requested.url];
                        const canBroker = requested.type === "popup"
                            && requestedURLs.length === 1
                            && typeof requestedURLs[0] === "string";

                        const operation = canBroker
                            ? brokeredPopupWindow(requested)
                            : new Promise((resolve, reject) => {
                                const finishNative = (value, error) => {
                                    if (
                                        !error
                                        && isNativeWindow(value)
                                    ) {
                                        resolve(value);
                                        return;
                                    }
                                    reject(
                                        error instanceof Error
                                            ? error
                                            : new Error(
                                                error?.message
                                                    ?? "WebKit rejected windows.create."
                                            )
                                    );
                                };

                                if (typeof nativeCreate !== "function") {
                                    finishNative(undefined, undefined);
                                    return;
                                }
                                invokeNativeWindow(
                                    nativeCreate,
                                    [requested],
                                    finishNative,
                                    3000
                                );
                            });
                        if (callback) {
                            operation.then(
                                (value) => callback(value),
                                (error) => invokeCallbackWithLastError(
                                    callback,
                                    error?.message
                                        ?? "WebKit did not answer windows.create."
                                )
                            );
                            return undefined;
                        }
                        return operation;
                    };

                    const update = (...inputArguments) => {
                        const args = Array.from(inputArguments);
                        const callback = typeof args.at(-1) === "function"
                            ? args.pop()
                            : undefined;
                        const windowID = args[0];
                        const requested = args[1]
                            && typeof args[1] === "object"
                            ? args[1]
                            : {};
                        const supported = Object.fromEntries(
                            Object.entries(requested).filter(
                                ([property]) =>
                                    !unsupportedWindowUpdateProperties.has(
                                        property
                                    )
                            )
                        );
                        const fallback = { id: windowID, ...requested };
                        let settled = false;
                        const settleCallback = (value = fallback) => {
                            if (settled || !callback) return;
                            settled = true;
                            try { callback(value ?? fallback); } catch (error) {
                                queueMicrotask(() => { throw error; });
                            }
                        };

                        // WebKit rejects Chrome's popup geometry fields and
                        // never calls the supplied callback. Crest presents
                        // extension pop-outs inside its own tab/window model,
                        // so those coordinates cannot be applied faithfully;
                        // treating them as a settled no-op preserves the
                        // browser-neutral API contract without resizing the
                        // user's main browser window.
                        if (Object.keys(supported).length === 0) {
                            if (callback) {
                                queueMicrotask(() => settleCallback(fallback));
                                return undefined;
                            }
                            return Promise.resolve(fallback);
                        }

                        let returned;
                        try {
                            returned = Reflect.apply(
                                nativeUpdate,
                                nativeWindows,
                                [
                                    windowID,
                                    supported,
                                    ...(callback ? [settleCallback] : [])
                                ]
                            );
                        } catch {
                            if (callback) {
                                queueMicrotask(() => settleCallback(fallback));
                                return undefined;
                            }
                            return Promise.resolve(fallback);
                        }
                        if (callback) {
                            if (returned?.then instanceof Function) {
                                returned.then(
                                    (value) => settleCallback(value),
                                    () => settleCallback(fallback)
                                );
                            } else if (returned !== undefined) {
                                settleCallback(returned);
                            }
                            return undefined;
                        }
                        return returned?.then instanceof Function
                            ? returned.catch(() => fallback)
                            : Promise.resolve(returned ?? fallback);
                    };
                    const overlays = new Map([["create", create]]);
                    if (typeof nativeUpdate === "function") {
                        overlays.set("update", update);
                    }
                    try {
                        const descriptor = Reflect.getOwnPropertyDescriptor(
                            nativeWindows,
                            "create"
                        );
                        Object.defineProperty(nativeWindows, "create", {
                            value: create,
                            writable: true,
                            configurable: true,
                            enumerable: descriptor?.enumerable ?? true
                        });
                    } catch {}
                    try {
                        if (nativeWindows.create === create) {
                            overlays.delete("create");
                        }
                    } catch {}
                    try {
                        const descriptor = Reflect.getOwnPropertyDescriptor(
                            nativeWindows,
                            "update"
                        );
                        Object.defineProperty(nativeWindows, "update", {
                            value: update,
                            writable: true,
                            configurable: true,
                            enumerable: descriptor?.enumerable ?? true
                        });
                    } catch {}
                    try {
                        if (nativeWindows.update === update) {
                            overlays.delete("update");
                        }
                    } catch {}
                    const normalized = overlays.size === 0
                        ? nativeWindows
                        : namespaceFacade(nativeWindows, {}, overlays);
                    normalizedWindowNamespaces.set(nativeWindows, normalized);
                    normalizedWindowNamespaces.set(normalized, normalized);
                    return normalized;
                };
                const normalizedStorageNamespaces = new WeakMap();
                const normalizeStorageNamespace = (nativeStorage) => {
                    if (!namespaceUsesCompatibility("storage")) {
                        return nativeStorage;
                    }
                    if (!nativeStorage) return nativeStorage;
                    if (normalizedStorageNamespaces.has(nativeStorage)) {
                        return normalizedStorageNamespaces.get(nativeStorage);
                    }

                    const rootListeners = new Set();
                    const areaListeners = new Map();
                    const event = (listeners) => Object.freeze({
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
                        hasListeners() {
                            return listeners.size > 0;
                        }
                    });
                    const listenersForArea = (areaName) => {
                        if (!areaListeners.has(areaName)) {
                            areaListeners.set(areaName, new Set());
                        }
                        return areaListeners.get(areaName);
                    };
                    const rootEvent = event(rootListeners);
                    const areaEvents = new Map();
                    // Chrome fires storage.onChanged for every write, even one
                    // that stores an identical value, so a value signature can
                    // never decide whether an event is a duplicate. Correlate
                    // by area and key set instead, and only across the two
                    // delivery paths: a Crest-originated event (this context's
                    // own mutation, or one relayed from a sibling extension
                    // page) and WebKit's native event. Two events from the same
                    // path are always two real writes.
                    const changeWindowMilliseconds = 250;
                    const recentEmissions = [];
                    const nativeObservedAreas = new Set();
                    const changeKeySignature = (changes, areaName) => {
                        try {
                            return JSON.stringify([
                                areaName,
                                Object.keys(changes ?? {}).sort()
                            ]);
                        } catch {
                            return undefined;
                        }
                    };
                    const pruneEmissions = (now) => {
                        while (
                            recentEmissions.length > 0
                            && now - recentEmissions[0].at
                                > changeWindowMilliseconds
                        ) {
                            recentEmissions.shift();
                        }
                    };
                    // Storage tracing rides the same gate as console capture
                    // and message tracing: with it off `reportRuntimeTrace` is
                    // the no-op assigned at the top of this runtime and these
                    // helpers return before touching anything. A storage call
                    // that never settles is otherwise completely silent —
                    // Bitwarden's worker takes `doFullSync` and goes quiet
                    // with a pending `storage.local.set` behind it — so the
                    // dispatch, the completion, and a synthesized completion
                    // have to be told apart.
                    //
                    // Names only, never values: this area IS the vault.
                    const storageTraceKeyLimit = 24;
                    const storageTraceKeyNames = (input) => {
                        if (Array.isArray(input)) {
                            return input.filter(
                                (key) => typeof key === "string"
                            );
                        }
                        if (typeof input === "string") return [input];
                        if (input && typeof input === "object") {
                            return Object.keys(input);
                        }
                        // `get(null)`, `get()` and `clear()` all address the
                        // whole area rather than a key list.
                        return undefined;
                    };
                    const storageTraceKeyText = (input) => {
                        let names;
                        try {
                            names = storageTraceKeyNames(input);
                        } catch {
                            return "(unreadable)";
                        }
                        if (names === undefined) return "(all)";
                        if (names.length === 0) return "(none)";
                        const shown = names.slice(0, storageTraceKeyLimit);
                        const remainder = names.length - shown.length;
                        return shown.join(",")
                            + (remainder > 0 ? `,+${remainder} more` : "");
                    };
                    const traceStorage = (op, message) => {
                        if (!capturesExtensionConsole) return;
                        reportRuntimeTrace(op, {
                            context: executionProcess,
                            message
                        });
                    };
                    const dispatchStorageChange = (
                        changes,
                        areaName,
                        origin
                    ) => {
                        if (!changes || typeof changes !== "object") return;
                        if (Object.keys(changes).length === 0) return;
                        const normalizedAreaName = typeof areaName === "string"
                            ? areaName
                            : "local";
                        const path = origin === "native" ? "native" : "crest";
                        if (capturesExtensionConsole) {
                            traceStorage(
                                `storage.${normalizedAreaName}.onChanged`,
                                `path=${origin} keys=${
                                    storageTraceKeyText(changes)
                                }`
                            );
                        }
                        const ownMutation = origin === "ownMutation";
                        const signature = changeKeySignature(
                            changes,
                            normalizedAreaName
                        );
                        const now = Date.now();
                        pruneEmissions(now);
                        if (signature !== undefined) {
                            // Correlation runs in one direction only: a native
                            // event may cancel a Crest emission that ALREADY
                            // happened, never a later one. A native event for
                            // key X raised by another context used to leave a
                            // token that swallowed this context's own next
                            // write of X — the exact case the relay exists for,
                            // where WebKit does not echo a context's own write,
                            // so the listener saw nothing at all. Only Crest
                            // emissions are recorded, and only a native arrival
                            // consumes one.
                            if (path === "native") {
                                const index = recentEmissions.findIndex(
                                    (entry) => entry.signature === signature
                                );
                                if (index >= 0) {
                                    const [matched] = recentEmissions.splice(
                                        index,
                                        1
                                    );
                                    if (matched.ownMutation) {
                                        // WebKit delivered this context's own
                                        // write natively. The relay only exists
                                        // to fill that gap, so stop
                                        // synthesizing for this area for the
                                        // life of the context.
                                        nativeObservedAreas.add(
                                            normalizedAreaName
                                        );
                                    }
                                    if (capturesExtensionConsole) {
                                        traceStorage(
                                            `storage.${
                                                normalizedAreaName
                                            }.onChangedCoalesced`,
                                            `path=native matched=${
                                                matched.ownMutation
                                                    ? "ownMutation"
                                                    : "relay"
                                            } keys=${
                                                storageTraceKeyText(changes)
                                            }`
                                        );
                                    }
                                    return;
                                }
                            } else {
                                recentEmissions.push({
                                    signature,
                                    ownMutation,
                                    at: now
                                });
                            }
                        }
                        for (const listener of Array.from(rootListeners)) {
                            try {
                                listener(changes, normalizedAreaName);
                            } catch {}
                        }
                        for (const listener of Array.from(
                            listenersForArea(normalizedAreaName)
                        )) {
                            try { listener(changes); } catch {}
                        }
                    };
                    const storageBridgeMarker =
                        "__crestWebExtensionStorageBridgeV1";
                    // A BroadcastChannel is scoped to the context's own
                    // origin. In a content script that origin is the HOST
                    // PAGE, so relaying there would hand every stored value to
                    // the page, let the page forge storage.onChanged, and let
                    // two extensions on one tab hear each other. Chrome
                    // delivers storage.onChanged to content scripts natively,
                    // so the relay exists only for privileged extension
                    // contexts, whose origin is the extension itself.
                    const storageBridgeScope = (() => {
                        try {
                            return new URL(extensionBaseURL).host
                                || extensionBaseURL;
                        } catch {
                            return extensionBaseURL;
                        }
                    })();
                    const storageBridgeChannelName =
                        storageBridgeMarker + ":" + storageBridgeScope;
                    let storageBridge;
                    if (isPrivilegedExtensionContext) {
                        try {
                            storageBridge = new BroadcastChannel(
                                storageBridgeChannelName
                            );
                            storageBridge.addEventListener(
                                "message",
                                (event) => {
                                    const payload = event.data
                                        ?.[storageBridgeMarker];
                                    if (
                                        payload?.version !== 1
                                        || payload.kind !== "storage-change"
                                        || payload.origin !== extensionBaseURL
                                        || typeof payload.areaName !== "string"
                                        || !payload.changes
                                        || typeof payload.changes !== "object"
                                    ) {
                                        return;
                                    }
                                    dispatchStorageChange(
                                        payload.changes,
                                        payload.areaName,
                                        "relay"
                                    );
                                }
                            );
                        } catch {
                            storageBridge = undefined;
                        }
                    }
                    const broadcastStorageChange = (changes, areaName) => {
                        if (!storageBridge) return;
                        if (!changes || typeof changes !== "object") return;
                        if (Object.keys(changes).length === 0) return;
                        try {
                            storageBridge.postMessage({
                                [storageBridgeMarker]: {
                                    version: 1,
                                    kind: "storage-change",
                                    origin: extensionBaseURL,
                                    changes,
                                    areaName
                                }
                            });
                        } catch {}
                    };
                    const nativeMethod = (target, property) => {
                        try {
                            const value = Reflect.get(
                                target,
                                property,
                                target
                            );
                            return typeof value === "function"
                                ? value
                                : undefined;
                        } catch {
                            return undefined;
                        }
                    };
                    const installInPlace = (target, property, value) => {
                        if (!target) return false;
                        try {
                            if (Reflect.get(target, property, target) === value) {
                                return true;
                            }
                        } catch {}
                        try {
                            const descriptor =
                                Reflect.getOwnPropertyDescriptor(
                                    target,
                                    property
                                );
                            Object.defineProperty(target, property, {
                                value,
                                writable: descriptor?.writable ?? true,
                                configurable:
                                    descriptor?.configurable ?? true,
                                enumerable: descriptor?.enumerable ?? true
                            });
                        } catch {
                            try {
                                Reflect.set(target, property, value, target);
                            } catch {}
                        }
                        try {
                            return Reflect.get(target, property, target) === value;
                        } catch {
                            return false;
                        }
                    };
                    const invokeNative = (
                        target,
                        method,
                        args,
                        completion,
                        completionFallbackDelay,
                        usesPromiseForm = false,
                        // Diagnostics only. Called from the fallback timer,
                        // just before the synthesized completion, so a trace
                        // reader can tell WebKit's own answer from Crest's
                        // stand-in. A no-op when tracing is off.
                        traceFallbackTimeout
                    ) => {
                        let completed = false;
                        let completionFallback;
                        const finish = (value, error) => {
                            if (completed) return;
                            completed = true;
                            if (completionFallback !== undefined) {
                                clearTimeout(completionFallback);
                            }
                            completion(value, error);
                        };
                        const callback = (value) => {
                            let lastError;
                            try { lastError = nativeRuntime?.lastError; } catch {}
                            finish(value, lastError);
                        };
                        let result;
                        try {
                            result = Reflect.apply(
                                method,
                                target,
                                usesPromiseForm
                                    ? args
                                    : [...args, callback]
                            );
                        } catch (error) {
                            finish(undefined, error);
                            return;
                        }
                        if (result?.then) {
                            Promise.resolve(result).then(
                                (value) => finish(value, undefined),
                                (error) => finish(undefined, error)
                            );
                            return;
                        }
                        if (result !== undefined) {
                            finish(result, undefined);
                            return;
                        }
                        if (
                            completionFallbackDelay !== undefined
                            && !completed
                        ) {
                            // A WebKit storage method can accept its operation
                            // without exposing either callback or Promise
                            // completion. Preserve the legacy bounded fallback
                            // only for that no-channel case. A real Promise is
                            // authoritative regardless of how long it takes:
                            // substituting an empty result while it is pending
                            // fabricates missing extension state.
                            completionFallback = setTimeout(
                                () => {
                                    if (
                                        typeof traceFallbackTimeout
                                            === "function"
                                    ) {
                                        try {
                                            traceFallbackTimeout();
                                        } catch {}
                                    }
                                    finish(undefined, undefined);
                                },
                                completionFallbackDelay
                            );
                        }
                    };
                    const storageChanges = (operation, input, previous) => {
                        const changes = {};
                        const oldValues = previous
                            && typeof previous === "object"
                            ? previous
                            : {};
                        if (operation === "set") {
                            const newValues = input
                                && typeof input === "object"
                                ? input
                                : {};
                            for (const [key, newValue] of Object.entries(
                                newValues
                            )) {
                                // Chrome and WebKit both order the change
                                // object as { oldValue, newValue }. Match it so
                                // a serialized Crest change is byte-identical
                                // to a native one.
                                const change = {};
                                if (Object.prototype.hasOwnProperty.call(
                                    oldValues,
                                    key
                                )) {
                                    change.oldValue = oldValues[key];
                                }
                                change.newValue = newValue;
                                changes[key] = change;
                            }
                        } else {
                            const keys = operation === "clear"
                                ? Object.keys(oldValues)
                                : (
                                    Array.isArray(input)
                                        ? input
                                        : [input]
                                ).filter((key) => typeof key === "string");
                            for (const key of keys) {
                                if (!Object.prototype.hasOwnProperty.call(
                                    oldValues,
                                    key
                                )) continue;
                                changes[key] = {
                                    oldValue: oldValues[key]
                                };
                            }
                        }
                        return changes;
                    };
                    const read = (
                        nativeArea,
                        areaName,
                        operation,
                        nativeGet
                    ) => (...args) => {
                        const callback = typeof args.at(-1) === "function"
                            ? args.pop()
                            : undefined;
                        const traceOp = `storage.${areaName}.${operation}`;
                        const keysText = capturesExtensionConsole
                            ? storageTraceKeyText(args[0])
                            : "";
                        traceStorage(
                            traceOp,
                            `keys=${keysText} form=${
                                callback ? "callback" : "promise"
                            }`
                        );
                        const promise = new Promise((resolve, reject) => {
                            invokeNative(
                                nativeArea,
                                nativeGet,
                                args,
                                (value, error) => {
                                    if (error) {
                                        traceStorage(
                                            `${traceOp}Rejected`,
                                            `keys=${keysText} error=${
                                                traceErrorText(error)
                                            }`
                                        );
                                    } else {
                                        traceStorage(
                                            `${traceOp}Resolved`,
                                            `keys=${keysText} returned=${
                                                capturesExtensionConsole
                                                    ? storageTraceKeyText(
                                                        value
                                                    )
                                                    : ""
                                            }`
                                        );
                                    }
                                    const result = value
                                        && typeof value === "object"
                                        ? value
                                        : {};
                                    if (callback) {
                                        try { callback(result); } catch (cause) {
                                            queueMicrotask(() => {
                                                throw cause;
                                            });
                                        }
                                    }
                                    if (error) reject(error);
                                    else resolve(result);
                                },
                                250,
                                true,
                                () => traceStorage(
                                    `${traceOp}FallbackTimeout`,
                                    `keys=${keysText} the native call returned`
                                        + " neither a promise nor a value and"
                                        + " no callback fired; Crest"
                                        + " synthesized an empty result after"
                                        + " 250ms"
                                )
                            );
                        });
                        if (callback) {
                            promise.catch(() => {});
                            return undefined;
                        }
                        return promise;
                    };
                    const mutation = (
                        nativeArea,
                        areaName,
                        operation,
                        nativeMutation
                    ) => (...args) => {
                        const callback = typeof args.at(-1) === "function"
                            ? args.pop()
                            : undefined;
                        const input = operation === "clear"
                            ? undefined
                            : args[0];
                        const nativeGet = nativeMethod(nativeArea, "get");
                        const readKeys = operation === "clear"
                            ? null
                            : operation === "set"
                                ? Object.keys(
                                    input && typeof input === "object"
                                        ? input
                                        : {}
                                )
                                : input;
                        const traceOp = `storage.${areaName}.${operation}`;
                        const keysText = capturesExtensionConsole
                            ? storageTraceKeyText(readKeys)
                            : "";
                        traceStorage(
                            traceOp,
                            `keys=${keysText} form=${
                                callback ? "callback" : "promise"
                            }`
                        );
                        const promise = new Promise((resolve, reject) => {
                            const performMutation = (previous) => {
                                invokeNative(
                                    nativeArea,
                                    nativeMutation,
                                    args,
                                    (_, error) => {
                                        if (error) {
                                            traceStorage(
                                                `${traceOp}Rejected`,
                                                `keys=${keysText} error=${
                                                    traceErrorText(error)
                                                }`
                                            );
                                        } else {
                                            traceStorage(
                                                `${traceOp}Resolved`,
                                                `keys=${keysText}`
                                            );
                                        }
                                        if (!error) {
                                            const changes = storageChanges(
                                                operation,
                                                input,
                                                previous
                                            );
                                            if (
                                                !nativeObservedAreas.has(
                                                    areaName
                                                )
                                            ) {
                                                dispatchStorageChange(
                                                    changes,
                                                    areaName,
                                                    "ownMutation"
                                                );
                                            }
                                            broadcastStorageChange(
                                                changes,
                                                areaName
                                            );
                                        }
                                        if (callback) {
                                            try { callback(); } catch (cause) {
                                                queueMicrotask(() => {
                                                    throw cause;
                                                });
                                            }
                                        }
                                        if (error) reject(error);
                                        else resolve(undefined);
                                    },
                                    250,
                                    true,
                                    () => traceStorage(
                                        `${traceOp}FallbackTimeout`,
                                        `keys=${keysText} the native call`
                                            + " returned neither a promise nor"
                                            + " a value and no callback fired;"
                                            + " Crest synthesized completion"
                                            + " after 250ms"
                                    )
                                );
                            };
                            if (!nativeGet) {
                                traceStorage(
                                    `${traceOp}PriorReadSkipped`,
                                    `keys=${keysText} this area exposes no`
                                        + " native get"
                                );
                                performMutation({});
                                return;
                            }
                            // The mutation cannot start until this read
                            // settles, so a read that never answers is
                            // indistinguishable, from the caller's side, from
                            // a write that never lands. Trace it separately.
                            traceStorage(
                                `${traceOp}PriorRead`,
                                `keys=${keysText}`
                            );
                            invokeNative(
                                nativeArea,
                                nativeGet,
                                [readKeys],
                                (previous, error) => {
                                    if (error) {
                                        traceStorage(
                                            `${traceOp}PriorReadRejected`,
                                            `keys=${keysText} error=${
                                                traceErrorText(error)
                                            }`
                                        );
                                    } else {
                                        traceStorage(
                                            `${traceOp}PriorReadResolved`,
                                            `keys=${keysText} returned=${
                                                capturesExtensionConsole
                                                    ? storageTraceKeyText(
                                                        previous
                                                    )
                                                    : ""
                                            }`
                                        );
                                    }
                                    performMutation(error ? {} : previous);
                                },
                                250,
                                true,
                                () => traceStorage(
                                    `${traceOp}PriorReadFallbackTimeout`,
                                    `keys=${keysText} the native get returned`
                                        + " neither a promise nor a value and"
                                        + " no callback fired; Crest"
                                        + " synthesized an empty result after"
                                        + " 250ms"
                                )
                            );
                        });
                        if (callback) {
                            promise.catch(() => {});
                            return undefined;
                        }
                        return promise;
                    };

                    let nativeRootOnChanged;
                    try {
                        nativeRootOnChanged = nativeStorage.onChanged;
                    } catch {}
                    const nativeRootAddListener = nativeMethod(
                        nativeRootOnChanged,
                        "addListener"
                    );
                    if (nativeRootAddListener) {
                        try {
                            Reflect.apply(
                                nativeRootAddListener,
                                nativeRootOnChanged,
                                [
                                    (changes, areaName) =>
                                        dispatchStorageChange(
                                            changes,
                                            areaName,
                                            "native"
                                        )
                                ]
                            );
                        } catch {}
                    }
                    installInPlace(nativeStorage, "onChanged", rootEvent);

                    const storageOverlays = new Map([
                        ["onChanged", rootEvent]
                    ]);
                    for (const areaName of [
                        "local", "sync", "session", "managed"
                    ]) {
                        let nativeArea;
                        try { nativeArea = nativeStorage[areaName]; } catch {}
                        if (!nativeArea) continue;
                        const areaEvent = event(listenersForArea(areaName));
                        areaEvents.set(areaName, areaEvent);
                        let nativeAreaOnChanged;
                        try {
                            nativeAreaOnChanged = nativeArea.onChanged;
                        } catch {}
                        const nativeAreaAddListener = nativeMethod(
                            nativeAreaOnChanged,
                            "addListener"
                        );
                        if (nativeAreaAddListener) {
                            try {
                                Reflect.apply(
                                    nativeAreaAddListener,
                                    nativeAreaOnChanged,
                                    [
                                        (changes) => dispatchStorageChange(
                                            changes,
                                            areaName,
                                            "native"
                                        )
                                    ]
                                );
                            } catch {}
                        }
                        installInPlace(nativeArea, "onChanged", areaEvent);
                        const areaOverlays = new Map([
                            ["onChanged", areaEvent]
                        ]);
                        const nativeGet = nativeMethod(nativeArea, "get");
                        if (nativeGet) {
                            areaOverlays.set(
                                "get",
                                read(nativeArea, areaName, "get", nativeGet)
                            );
                        }
                        for (const operation of [
                            "set", "remove", "clear"
                        ]) {
                            const nativeMutation = nativeMethod(
                                nativeArea,
                                operation
                            );
                            if (!nativeMutation) continue;
                            areaOverlays.set(
                                operation,
                                mutation(
                                    nativeArea,
                                    areaName,
                                    operation,
                                    nativeMutation
                                )
                            );
                        }
                        for (const [property, value] of areaOverlays) {
                            installInPlace(nativeArea, property, value);
                        }
                        storageOverlays.set(
                            areaName,
                            namespaceFacade(
                                nativeArea,
                                {},
                                areaOverlays
                            )
                        );
                    }
                    const facade = namespaceFacade(
                        nativeStorage,
                        {},
                        storageOverlays
                    );
                    normalizedStorageNamespaces.set(nativeStorage, facade);
                    normalizedStorageNamespaces.set(facade, facade);
                    return facade;
                };
                const nativeCapabilityNames = \(availableNamespacesLiteral);
                // WebKit publishes `chrome` and `browser` as two facades over
                // one extension context, and either can carry a namespace the
                // other lacks. Copying across closes that gap for the routes
                // where WebKit's implementation is the one packages should
                // get. It must not run for a namespace routed `emulated`:
                // there, Crest's object is the contract, and `installFallbacks`
                // below installs it on both roots — aliasing first would let a
                // native implementation reach one root and win by arriving
                // earlier. `nativeCapabilityNames` already excludes namespaces
                // routed `unavailable`; the guard states it rather than
                // relying on that.
                const installNativeAliases = (target, source) => {
                    if (!target || !source || target === source) return;
                    for (const property of nativeCapabilityNames) {
                        if (!namespaceIsAliasable(property)) continue;
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
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {}
                    }
                };
                installNativeAliases(nativeChrome, nativeBrowser);
                installNativeAliases(nativeBrowser, nativeChrome);
                // The same rule one level down. Every storage area is routed
                // `nativePatched` today, so all four cross-copy; an area moved
                // to `emulated` would stop, because Crest's area object would
                // then be the contract rather than a gap filler.
                const installStorageAreaAliases = (targetRoot, sourceRoot) => {
                    if (!namespaceIsAliasable("storage")) return;
                    let targetStorage;
                    let sourceStorage;
                    try {
                        targetStorage = targetRoot?.storage;
                        sourceStorage = sourceRoot?.storage;
                    } catch {}
                    if (!targetStorage || !sourceStorage) return;
                    for (const areaName of [
                        "local", "sync", "session", "managed"
                    ]) {
                        if (crestOwnsPath(`storage.${areaName}`)) continue;
                        let currentArea;
                        let sourceArea;
                        try {
                            currentArea = targetStorage[areaName];
                            sourceArea = sourceStorage[areaName];
                        } catch {
                            continue;
                        }
                        if (
                            currentArea !== undefined
                            || sourceArea === undefined
                        ) {
                            continue;
                        }
                        try {
                            Object.defineProperty(
                                targetStorage,
                                areaName,
                                {
                                    value: sourceArea,
                                    writable: true,
                                    configurable: true,
                                    enumerable: true
                                }
                            );
                        } catch {
                            try { targetStorage[areaName] = sourceArea; } catch {}
                        }
                    }
                };
                installStorageAreaAliases(nativeChrome, nativeBrowser);
                installStorageAreaAliases(nativeBrowser, nativeChrome);
                const installedRoots = new Set();
                for (const root of [nativeChrome, nativeBrowser]) {
                    if (!root || installedRoots.has(root)) continue;
                    installedRoots.add(root);
                    installCompatibility(root);
                }
                // This must never wrap a namespace WebKit owns.
                //
                // WebKit resolves extension event targets by reading each
                // frame's live `chrome` / `browser` global and unwrapping the
                // NATIVE object behind the namespace property. A JavaScript
                // Proxy has no native wrapper, so a facade installed over a
                // live native namespace strands every listener registered
                // through it — the same failure the root-level comment below
                // records, one level down, and the one that broke WebKit
                // message routing outright on 2026-08-29 when a root was
                // replaced with a Proxy.
                //
                // So a `native` or `nativePatched` namespace that already
                // exists is left exactly as WebKit published it. Its missing
                // members were filled in place by `installFallbacks` above,
                // which is the only augmentation that survives WebKit's
                // unwrapping. Only an `emulated` namespace may be replaced,
                // and it is replaced with Crest's own plain object — never a
                // Proxy over the native one. The handful of namespaces that
                // genuinely cannot be augmented in place keep their existing
                // `normalize*Namespace` path, unchanged; no new wrapping is
                // introduced here.
                //
                // This function looked like it did more until 2026-09, but
                // `installFallbacks` pinned every namespace it touched
                // non-configurable, so each `defineProperty` below threw and
                // was swallowed: facades were never installed over existing
                // native namespaces. Removing that pinning — it broke
                // extensions that legitimately monkeypatch `chrome.*` — must
                // not resurrect the wrapping it was suppressing by accident.
                const installNamespaceFacades = (root, alternateRoot) => {
                    if (!root) return;
                    const fallbacks = fallbacksFor(root);
                    for (const property of nativeCapabilityNames) {
                        // runtime methods and Port/event objects are owned by
                        // WebKit's extension context. Keep that namespace
                        // native for both browser and chrome roots; missing
                        // compatible members were already added in place by
                        // installCompatibility above.
                        if (property === "runtime") continue;
                        let nativeValue;
                        try { nativeValue = root[property]; } catch {}
                        if (
                            nativeValue === undefined
                            && alternateRoot
                            && namespaceIsAliasable(property)
                        ) {
                            try {
                                nativeValue = alternateRoot[property];
                            } catch {}
                        }
                        if (property === "storage") {
                            nativeValue = normalizeStorageNamespace(
                                nativeValue
                            );
                        }
                        if (property === "extension") {
                            const originalExtension = nativeValue;
                            nativeValue = normalizeExtensionNamespace(
                                nativeValue
                            );
                            if (nativeValue !== originalExtension) {
                                try {
                                    Object.defineProperty(root, property, {
                                        value: nativeValue,
                                        writable: true,
                                        configurable: true,
                                        enumerable: true
                                    });
                                } catch {
                                    try { root[property] = nativeValue; } catch {}
                                }
                            }
                        }
                        if (property === "alarms") {
                            const originalAlarms = nativeValue;
                            nativeValue = normalizeAlarmsNamespace(
                                nativeValue
                            );
                            if (nativeValue !== originalAlarms) {
                                try {
                                    Object.defineProperty(root, property, {
                                        value: nativeValue,
                                        writable: true,
                                        configurable: true,
                                        enumerable: true
                                    });
                                } catch {
                                    try { root[property] = nativeValue; } catch {}
                                }
                            }
                        }
                        const fallback = fallbacks[property];
                        if (fallback === undefined) continue;
                        // `native` and `nativePatched`: WebKit's object
                        // stands, whole. Nothing to do — see above.
                        if (!crestOwnsPath(property)) continue;
                        // `emulated`: Crest's plain object, and only if
                        // `installFallbacks` has not already put it there.
                        if (nativeValue === fallback) continue;
                        try {
                            Object.defineProperty(root, property, {
                                value: fallback,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch {
                            try { root[property] = fallback; } catch {}
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
                            writable: true,
                            configurable: true,
                            enumerable: true
                        });
                    } catch {
                        try { globalThis[name] = root; } catch {}
                    }
                };
                installMissingRoot("chrome", nativeBrowser);
                installMissingRoot("browser", nativeChrome);
                // WebKit resolves extension event targets by reading each
                // frame's live `browser` and `chrome` globals and unwrapping
                // the native namespace object. A JavaScript Proxy has no
                // native wrapper, so replacing both roots leaves registered
                // runtime listeners undispatchable. Keep every WebKit-owned
                // global root intact; compatibility namespaces were installed
                // in place above, and worker-only facades remain lexical below.
                const rootFacadeCache = new WeakMap();
                const rootFacade = (root, alternateRoot) => {
                    if (!root) return root;
                    if (rootFacadeCache.has(root)) {
                        return rootFacadeCache.get(root);
                    }
                    const overlays = new Map();
                    const directNamespace = (property) => {
                        try { return root[property]; } catch {}
                        return undefined;
                    };
                    const currentNamespace = (property) => {
                        let value = directNamespace(property);
                        if (
                            value === undefined
                            && alternateRoot
                            && namespaceIsAliasable(property)
                        ) {
                            try { value = alternateRoot[property]; } catch {}
                        }
                        return value;
                    };

                    const nativeI18n = currentNamespace("i18n");
                    const normalizedI18n = normalizeI18n(nativeI18n);
                    if (normalizedI18n !== directNamespace("i18n")) {
                        overlays.set("i18n", normalizedI18n);
                    }
                    for (const property of ["menus", "contextMenus"]) {
                        const nativeMenus = currentNamespace(property);
                        const normalizedMenus = normalizeMenuNamespace(
                            nativeMenus
                        );
                        if (normalizedMenus !== directNamespace(property)) {
                            overlays.set(property, normalizedMenus);
                        }
                    }
                    const nativePermissions = currentNamespace("permissions");
                    const normalizedPermissions =
                        normalizePermissionsNamespace(nativePermissions);
                    if (
                        normalizedPermissions
                        !== directNamespace("permissions")
                    ) {
                        overlays.set("permissions", normalizedPermissions);
                    }
                    const nativeWindows = currentNamespace("windows");
                    const normalizedWindows =
                        normalizeWindowsNamespace(nativeWindows);
                    if (normalizedWindows !== directNamespace("windows")) {
                        overlays.set("windows", normalizedWindows);
                    }
                    const nativeExtension = currentNamespace("extension");
                    const normalizedExtension =
                        normalizeExtensionNamespace(nativeExtension);
                    if (
                        normalizedExtension !== directNamespace("extension")
                    ) {
                        overlays.set("extension", normalizedExtension);
                    }
                    const nativeAlarms = currentNamespace("alarms");
                    const normalizedAlarms =
                        normalizeAlarmsNamespace(nativeAlarms);
                    if (normalizedAlarms !== directNamespace("alarms")) {
                        overlays.set("alarms", normalizedAlarms);
                    }
                    const nativeTabs = currentNamespace("tabs");
                    const normalizedTabs = normalizeTabsNamespace(nativeTabs);
                    if (normalizedTabs !== directNamespace("tabs")) {
                        overlays.set("tabs", normalizedTabs);
                    }
                    const nativeWebNavigation =
                        currentNamespace("webNavigation");
                    const normalizedWebNavigation =
                        normalizeWebNavigationNamespace(
                            nativeWebNavigation,
                            normalizedTabs
                        );
                    if (
                        normalizedWebNavigation
                        !== directNamespace("webNavigation")
                    ) {
                        overlays.set(
                            "webNavigation",
                            normalizedWebNavigation
                        );
                    }
                    const nativeWebRequest = currentNamespace("webRequest");
                    const normalizedWebRequest =
                        normalizeWebRequestNamespace(nativeWebRequest);
                    if (
                        normalizedWebRequest
                        !== directNamespace("webRequest")
                    ) {
                        overlays.set("webRequest", normalizedWebRequest);
                    }
                    const nativeStorage = currentNamespace("storage");
                    const normalizedStorage =
                        normalizeStorageNamespace(nativeStorage);
                    if (normalizedStorage !== directNamespace("storage")) {
                        overlays.set("storage", normalizedStorage);
                    }
                    const nativeRuntime = currentNamespace("runtime");
                    if (nativeRuntime !== directNamespace("runtime")) {
                        overlays.set("runtime", nativeRuntime);
                    }
                    const facade = overlays.size === 0
                        ? root
                        : namespaceFacade(root, {}, overlays);
                    rootFacadeCache.set(root, facade);
                    return facade;
                };
                const workerScopedRoot = (root, alternateRoot) => {
                    if (!root) return root;
                    // Reading a namespace off this root, falling back to
                    // the sibling facade only where the route says WebKit's
                    // implementation is the one packages should get. A
                    // namespace Crest owns (`emulated`) or refuses
                    // (`unavailable`) is never borrowed across roots.
                    const workerNamespace = (property) => {
                        let value;
                        try { value = root[property]; } catch {}
                        if (
                            value === undefined
                            && alternateRoot
                            && namespaceIsAliasable(property)
                        ) {
                            try { value = alternateRoot[property]; } catch {}
                        }
                        return value;
                    };
                    const nativeExtension = workerNamespace("extension");
                    const workerRuntime = workerNamespace("runtime");
                    const workerTabs = workerNamespace("tabs");
                    const workerWebNavigation =
                        workerNamespace("webNavigation");
                    const workerWebRequest = workerNamespace("webRequest");
                    const normalizedExtension =
                        normalizeExtensionNamespace(nativeExtension);
                    const normalizedRuntime =
                        normalizeWorkerRuntimeNamespace(workerRuntime);
                    const normalizedTabs =
                        normalizeTabsNamespace(workerTabs);
                    const normalizedWebNavigation =
                        normalizeWebNavigationNamespace(
                            workerWebNavigation,
                            normalizedTabs
                        );
                    const normalizedWebRequest =
                        normalizeWebRequestNamespace(workerWebRequest);
                    const overlays = new Map([
                        ["extension", normalizedExtension],
                        ["runtime", normalizedRuntime],
                        ["tabs", normalizedTabs],
                        ["webNavigation", normalizedWebNavigation],
                        ["webRequest", normalizedWebRequest]
                    ]);
                    for (const [property, fallback] of Object.entries(
                        fallbacksFor(root)
                    )) {
                        if (
                            property === "runtime"
                            || property === "tabs"
                            || property === "webNavigation"
                            || property === "webRequest"
                        ) {
                            continue;
                        }
                        const nativeValue = workerNamespace(property);
                        const preparedValue = namespaceFacade(
                            nativeValue,
                            fallback
                        );
                        if (preparedValue !== nativeValue) {
                            overlays.set(property, preparedValue);
                        }
                    }
                    return namespaceFacade(
                        root,
                        {},
                        overlays
                    );
                };
                const scopedChrome = isBackgroundWorker
                    ? workerScopedRoot(
                        nativeChrome ?? nativeBrowser,
                        nativeBrowser
                    )
                    : rootFacade(
                        nativeChrome ?? nativeBrowser,
                        nativeBrowser
                    );
                const scopedBrowser = isBackgroundWorker
                    ? workerScopedRoot(
                        nativeBrowser ?? nativeChrome,
                        nativeChrome
                    )
                    : rootFacade(
                        nativeBrowser ?? nativeChrome,
                        nativeChrome
                    );
                try {
                    Object.defineProperty(
                        globalThis,
                        scopedCompatibilityAPIName,
                        {
                            value: Object.freeze({
                                chrome: scopedChrome,
                                browser: scopedBrowser
                            }),
                            configurable: false
                        }
                    );
                } catch {}
            })();
            """
    }

}

typealias BrowserChromeWebStoreCompatibilityPackagePreparer =
    BrowserWebExtensionCompatibilityPackagePreparer
