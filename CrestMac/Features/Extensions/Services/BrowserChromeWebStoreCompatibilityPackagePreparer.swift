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
    private static let preparationLock = NSLock()
    private static let preparedDigestFilename = ".crest-prepared-digest"
    private static let scopedCompatibilityAPIName =
        "__crestWebExtensionScopedAPI"
    private static let legacyBackgroundPreludePattern =
        #"(?s)\A// Crest's WKWebExtension host currently has no notifications API\.\s*.*?Object\.defineProperty\(globalThis, \"chrome\", \{\s*value: crestChromeCompatibility,\s*configurable: true\s*\}\);\s*\}\s*"#

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
            let manifestPermissions = try Self.requiredPermissionNames(
                in: stagingResourceURL
            )
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
                    ),
                allowsInternalCapabilityBroker: true
            )
        } catch {
            try? fileManager.removeItem(at: stagingRootURL)
            throw error
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
            failsWorkerWebSockets: failsWorkerWebSockets
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

    private static func requiredPermissionNames(
        in resourceURL: URL
    ) throws -> [String] {
        let manifestURL = resourceURL.appending(path: "manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        return manifest?["permissions"] as? [String] ?? []
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
        runtimeIdentity: BrowserExtensionRuntimeIdentity,
        failsWorkerWebSockets: Bool
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
        let appendsChromiumNavigatorFamilyMarker =
            runtimeIdentity.referenceEnvironment == .chromium
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
                const compatibilityPermissionNames = new Set(
                    \(compatibilityPermissionsLiteral)
                );
                const namespaceRoutes = Object.freeze(
                    \(namespaceRoutesLiteral)
                );
                const memberRoutes = Object.freeze(\(memberRoutesLiteral));
                const namespaceProcesses = Object.freeze(
                    \(namespaceProcessesLiteral)
                );
                const memberProcesses = Object.freeze(
                    \(memberProcessesLiteral)
                );
                const executionProcess = isBackgroundContext
                    ? "background"
                    : isPrivilegedExtensionContext
                        ? "extensionPage"
                        : "contentScript";
                const supportsProcess = (processes) =>
                    Array.isArray(processes)
                    && processes.includes(executionProcess);
                const namespaceUsesCompatibility = (namespace) =>
                    supportsProcess(namespaceProcesses[namespace])
                    && (
                        namespaceRoutes[namespace] === "nativePatched"
                        || namespaceRoutes[namespace] === "emulated"
                    );
                const memberUsesCompatibility = (path) =>
                    supportsProcess(memberProcesses[path])
                    && (
                        memberRoutes[path] === "nativePatched"
                        || memberRoutes[path] === "emulated"
                    );
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

                const installFailingWorkerWebSocket = () => {
                    if (!failsWorkerWebSockets || !isBackgroundWorker) {
                        return;
                    }
                    const NativeWebSocket = globalThis.WebSocket;
                    if (typeof NativeWebSocket !== "function") return;

                    // WebKit 27 hosts extension worker callbacks on the
                    // WebContent main thread, but its worker WebSocket channel
                    // synchronously posts bridge setup back to that same thread
                    // and waits on a semaphore. Constructing the native socket
                    // therefore deadlocks the entire process, including popup
                    // and extension-page loads. Report the connection as a
                    // standards-shaped asynchronous network failure instead:
                    // clients retain their normal retry/fallback behavior, and
                    // the worker remains able to service runtime messages.
                    const CONNECTING = NativeWebSocket.CONNECTING ?? 0;
                    const OPEN = NativeWebSocket.OPEN ?? 1;
                    const CLOSING = NativeWebSocket.CLOSING ?? 2;
                    const CLOSED = NativeWebSocket.CLOSED ?? 3;
                    class FailingWebSocket extends EventTarget {
                        static CONNECTING = CONNECTING;
                        static OPEN = OPEN;
                        static CLOSING = CLOSING;
                        static CLOSED = CLOSED;

                        constructor(url, protocols) {
                            super();
                            const resolvedURL = new URL(
                                String(url),
                                globalThis.location?.href
                            );
                            if (
                                resolvedURL.protocol !== "ws:"
                                && resolvedURL.protocol !== "wss:"
                            ) {
                                throw new DOMException(
                                    "WebSocket URL must use ws or wss.",
                                    "SyntaxError"
                                );
                            }
                            this._url = resolvedURL.href;
                            this._protocols = protocols;
                            this._binaryType = "blob";
                            this._readyState = CONNECTING;
                            this.onopen = null;
                            this.onmessage = null;
                            this.onerror = null;
                            this.onclose = null;
                            globalThis.setTimeout(() => this._fail(), 0);
                        }

                        get url() { return this._url; }
                        get readyState() { return this._readyState; }
                        get bufferedAmount() { return 0; }
                        get extensions() { return ""; }
                        get protocol() { return ""; }
                        get binaryType() { return this._binaryType; }
                        set binaryType(value) {
                            if (value !== "blob" && value !== "arraybuffer") {
                                return;
                            }
                            this._binaryType = value;
                        }

                        _dispatch(event) {
                            super.dispatchEvent(event);
                            const handler = this[`on${event.type}`];
                            if (typeof handler === "function") {
                                try { handler.call(this, event); } catch {}
                            }
                        }

                        _fail() {
                            if (this._readyState !== CONNECTING) {
                                if (this._readyState === CLOSING) {
                                    this._readyState = CLOSED;
                                    this._dispatch(new CloseEvent("close", {
                                        code: 1006,
                                        wasClean: false
                                    }));
                                }
                                return;
                            }
                            this._readyState = CLOSED;
                            this._dispatch(new Event("error"));
                            this._dispatch(new CloseEvent("close", {
                                code: 1006,
                                wasClean: false
                            }));
                        }

                        send(data) {
                            if (this._readyState === CONNECTING) {
                                throw new DOMException(
                                    "WebSocket is still connecting.",
                                    "InvalidStateError"
                                );
                            }
                            if (this._readyState !== OPEN) return;
                            void data;
                        }

                        close(code, reason) {
                            if (
                                this._readyState === CLOSING
                                || this._readyState === CLOSED
                            ) {
                                return;
                            }
                            this._readyState = CLOSING;
                            void code;
                            void reason;
                        }
                    }
                    for (const [name, value] of Object.entries({
                        CONNECTING,
                        OPEN,
                        CLOSING,
                        CLOSED
                    })) {
                        Object.defineProperty(
                            FailingWebSocket.prototype,
                            name,
                            { value, enumerable: true }
                        );
                    }
                    Object.defineProperty(
                        FailingWebSocket.prototype,
                        Symbol.toStringTag,
                        { value: "WebSocket" }
                    );
                    try {
                        Object.defineProperty(globalThis, "WebSocket", {
                            value: FailingWebSocket,
                            configurable: true,
                            writable: true
                        });
                    } catch {}
                    try {
                        console.warn(
                            "WebSocket is unavailable in background workers "
                                + "in this browser; connection failed."
                        );
                    } catch {}
                };
                installFailingWorkerWebSocket();

                const topFrameMessageTransportKey =
                    "__crestWebExtensionTopFrameMessage";
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
                        return Reflect.apply(
                            nativeAddListener,
                            nativeEvent,
                            [wrapperFor(listener)]
                        );
                    };
                    const removeListener = (listener) => {
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
                            configurable: true,
                            enumerable: descriptor?.enumerable ?? true
                        });
                    } catch {
                        try { nativeRuntime.getURL = getURL; } catch {}
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
                    const normalizeTab = (tab) => {
                        if (!tab || typeof tab !== "object") return tab;
                        if (typeof tab.discarded === "boolean") return tab;
                        const hasSize =
                            typeof tab.width === "number"
                            && typeof tab.height === "number";
                        if (!hasSize) return tab;
                        return {
                            ...tab,
                            discarded: tab.width === 0 && tab.height === 0,
                            autoDiscardable:
                                typeof tab.autoDiscardable === "boolean"
                                    ? tab.autoDiscardable
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
                        ? (...inputArguments) => invokeTransformed(
                            nativeGet,
                            inputArguments,
                            normalizeTab
                        )
                        : nativeGet;
                    const query = typeof nativeQuery === "function"
                        && memberUsesCompatibility("tabs.query")
                        ? (...inputArguments) => {
                            const args = Array.from(inputArguments);
                            const callback = typeof args.at(-1) === "function"
                                ? args.pop()
                                : undefined;
                            const requested = args[0]
                                && typeof args[0] === "object"
                                ? args[0].discarded
                                : undefined;
                            if (typeof requested === "boolean") {
                                args[0] = { ...args[0] };
                                delete args[0].discarded;
                            }
                            const transform = (tabs) => {
                                if (!Array.isArray(tabs)) return tabs;
                                const normalized = tabs.map(normalizeTab);
                                return typeof requested === "boolean"
                                    ? normalized.filter(
                                        (tab) => tab.discarded === requested
                                    )
                                    : normalized;
                            };
                            if (callback) args.push(callback);
                            return invokeTransformed(
                                nativeQuery,
                                args,
                                transform
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
                const normalizeWebRequestEvent = (nativeEvent) => {
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
                    const addListener = (listener, ...args) => Reflect.apply(
                        nativeAddListener,
                        nativeEvent,
                        [wrappedListener(listener), ...args]
                    );
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
                    for (const property of [
                        "onBeforeRequest",
                        "onBeforeSendHeaders",
                        "onSendHeaders",
                        "onHeadersReceived",
                        "onAuthRequired",
                        "onBeforeRedirect",
                        "onResponseStarted",
                        "onCompleted",
                        "onErrorOccurred",
                        "onActionIgnored"
                    ]) {
                        let nativeEvent;
                        try { nativeEvent = nativeWebRequest[property]; } catch {}
                        const normalizedEvent = normalizeWebRequestEvent(
                            nativeEvent
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

                    const containsOperation = (request) => {
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
                            partition.nativeRequest
                        );
                    };
                    const contains = (...args) => permissionCallbackOrPromise(
                        args,
                        containsOperation(args[0])
                    );
                    const getAllOperation = () => new Promise((resolve) => {
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
                            () => settle({permissions: [], origins: []}),
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
                    const getAll = (...args) => permissionCallbackOrPromise(
                        args,
                        getAllOperation()
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
                const serviceWorkerClients = Object.freeze({
                    async matchAll() {
                        // Chrome's WorkerGlobalScope.clients returns structured
                        // WindowClient handles. WebKit does not provide that
                        // API here, and chrome.extension.getViews() instead
                        // exposes live cross-context DOMWindow wrappers. Those
                        // wrappers become stale as a popup reloads and can crash
                        // WebKit when worker code reads location or document.
                        // An empty match is the only safe conservative fallback
                        // until WebKit supplies real worker clients.
                        return [];
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
                        !isPrivilegedExtensionContext
                        ||
                        notificationWatchPort
                        || notificationListenerCount() === 0
                    ) {
                        return;
                    }
                    const runtime = nativeRuntimeWithMethod(
                        "connectNative"
                    );
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
                        !isPrivilegedExtensionContext
                        ||
                        idleWatchPort
                        || idleStateChangeListeners.size === 0
                    ) {
                        return;
                    }
                    const runtime = nativeRuntimeWithMethod(
                        "connectNative"
                    );
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
                    handlerBehaviorChanged(...args) {
                        return callbackOrPromise(args);
                    }
                };
                // WebKit 27 exposes the core navigation lifecycle and frame
                // query methods, but omits four events present in both the
                // Chromium and Firefox schemas. Preserve feature registration
                // without claiming delivery semantics. Native members always
                // win, so a future WebKit implementation replaces these
                // presence-only fallbacks automatically.
                const webNavigation = {
                    onCreatedNavigationTarget: noopEvent,
                    onHistoryStateUpdated: noopEvent,
                    onReferenceFragmentUpdated: noopEvent,
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
                const fallbacksFor = (nativeRoot) => {
                    void nativeRoot;
                    const fallbacks = {
                        action,
                        browserAction: action,
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
                        if (Object.keys(members).length > 0) {
                            routedFallbacks.push([namespace, members]);
                        }
                    }
                    return Object.fromEntries(routedFallbacks);
                };
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
                        false
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
                    const foregroundOnlyMethods = new Set([
                        "getViews",
                        "getBackgroundPage"
                    ]);
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
                    const normalized = namespaceFacade(
                        nativeRuntime,
                        {},
                        new Map(),
                        new Set(["getBackgroundPage"])
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
                    if (alarmBridge) return;
                    try {
                        alarmBridge = new BroadcastChannel(
                            alarmBridgeMarker
                        );
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
                };
                const normalizeAlarmsNamespace = (nativeAlarms) => {
                    if (
                        !namespaceUsesCompatibility("alarms")
                        || !nativeAlarms
                        || !hasMV3ServiceWorker
                    ) {
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
                    installAlarmBroadcastBridge();
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
                                () => callback(undefined)
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
                    const recentChanges = new Map();
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
                    const changeSignature = (changes, areaName) => {
                        try {
                            return JSON.stringify([
                                areaName,
                                Object.keys(changes ?? {}).sort().map(
                                    (key) => [key, changes[key]]
                                )
                            ]);
                        } catch {
                            return undefined;
                        }
                    };
                    const dispatchStorageChange = (changes, areaName) => {
                        if (!changes || typeof changes !== "object") return;
                        if (Object.keys(changes).length === 0) return;
                        const normalizedAreaName = typeof areaName === "string"
                            ? areaName
                            : "local";
                        const signature = changeSignature(
                            changes,
                            normalizedAreaName
                        );
                        const now = Date.now();
                        for (const [key, timestamp] of recentChanges) {
                            if (now - timestamp > 250) {
                                recentChanges.delete(key);
                            }
                        }
                        if (
                            signature !== undefined
                            && recentChanges.has(signature)
                        ) {
                            return;
                        }
                        if (signature !== undefined) {
                            recentChanges.set(signature, now);
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
                    let storageBridge;
                    try {
                        storageBridge = new BroadcastChannel(
                            storageBridgeMarker
                        );
                        storageBridge.addEventListener(
                            "message",
                            (event) => {
                                const payload = event.data
                                    ?.[storageBridgeMarker];
                                if (
                                    payload?.version !== 1
                                    || payload.kind !== "storage-change"
                                    || typeof payload.areaName !== "string"
                                    || !payload.changes
                                    || typeof payload.changes !== "object"
                                ) {
                                    return;
                                }
                                dispatchStorageChange(
                                    payload.changes,
                                    payload.areaName
                                );
                            }
                        );
                    } catch {}
                    const broadcastStorageChange = (changes, areaName) => {
                        if (!storageBridge) return;
                        if (!changes || typeof changes !== "object") return;
                        if (Object.keys(changes).length === 0) return;
                        try {
                            storageBridge.postMessage({
                                [storageBridgeMarker]: {
                                    version: 1,
                                    kind: "storage-change",
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
                        usesPromiseForm = false
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
                                () => finish(undefined, undefined),
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
                                const change = { newValue };
                                if (Object.prototype.hasOwnProperty.call(
                                    oldValues,
                                    key
                                )) {
                                    change.oldValue = oldValues[key];
                                }
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
                    const read = (nativeArea, nativeGet) => (...args) => {
                        const callback = typeof args.at(-1) === "function"
                            ? args.pop()
                            : undefined;
                        const promise = new Promise((resolve, reject) => {
                            invokeNative(
                                nativeArea,
                                nativeGet,
                                args,
                                (value, error) => {
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
                                true
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
                        const promise = new Promise((resolve, reject) => {
                            const performMutation = (previous) => {
                                invokeNative(
                                    nativeArea,
                                    nativeMutation,
                                    args,
                                    (_, error) => {
                                        if (!error) {
                                            const changes = storageChanges(
                                                operation,
                                                input,
                                                previous
                                            );
                                            dispatchStorageChange(
                                                changes,
                                                areaName
                                            );
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
                                    true
                                );
                            };
                            if (!nativeGet) {
                                performMutation({});
                                return;
                            }
                            invokeNative(
                                nativeArea,
                                nativeGet,
                                [readKeys],
                                (previous, error) => {
                                    performMutation(error ? {} : previous);
                                },
                                250,
                                true
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
                                [dispatchStorageChange]
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
                                            areaName
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
                                read(nativeArea, nativeGet)
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
                const installStorageAreaAliases = (targetRoot, sourceRoot) => {
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
                        if (nativeValue === undefined && alternateRoot) {
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
                        const explicitOverlays = property === "runtime"
                            ? new Map()
                            : new Map();
                        let facade = namespaceFacade(
                            nativeValue,
                            fallback,
                            explicitOverlays
                        );
                        if (facade === nativeValue) continue;
                        try {
                            Object.defineProperty(root, property, {
                                get() { return facade; },
                                set(value) {
                                    nativeValue = value;
                                    facade = namespaceFacade(
                                        nativeValue,
                                        fallback,
                                        explicitOverlays
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
                        if (value === undefined && alternateRoot) {
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
                    let nativeExtension;
                    let workerRuntime;
                    let workerTabs;
                    let workerWebNavigation;
                    let workerWebRequest;
                    try { nativeExtension = root.extension; } catch {}
                    try { workerRuntime = root.runtime; } catch {}
                    try { workerTabs = root.tabs; } catch {}
                    try {
                        workerWebNavigation = root.webNavigation;
                    } catch {}
                    try { workerWebRequest = root.webRequest; } catch {}
                    if (nativeExtension === undefined && alternateRoot) {
                        try {
                            nativeExtension = alternateRoot.extension;
                        } catch {}
                    }
                    if (workerRuntime === undefined && alternateRoot) {
                        try { workerRuntime = alternateRoot.runtime; } catch {}
                    }
                    if (workerTabs === undefined && alternateRoot) {
                        try { workerTabs = alternateRoot.tabs; } catch {}
                    }
                    if (
                        workerWebNavigation === undefined
                        && alternateRoot
                    ) {
                        try {
                            workerWebNavigation =
                                alternateRoot.webNavigation;
                        } catch {}
                    }
                    if (workerWebRequest === undefined && alternateRoot) {
                        try {
                            workerWebRequest = alternateRoot.webRequest;
                        } catch {}
                    }
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
                        let nativeValue;
                        try { nativeValue = root[property]; } catch {}
                        if (nativeValue === undefined && alternateRoot) {
                            try {
                                nativeValue = alternateRoot[property];
                            } catch {}
                        }
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
