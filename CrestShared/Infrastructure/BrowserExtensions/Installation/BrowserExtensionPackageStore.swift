import CryptoKit
import Foundation

final class BrowserExtensionPackageStore: BrowserExtensionPackageStoring {
    private static let maximumDirectoryEntryCount =
        BrowserLocalExtensionPackage.maximumDirectoryEntryCount
    private static let maximumDirectoryByteCount =
        BrowserLocalExtensionPackage.maximumDirectoryByteCount
    private static let maximumArchiveByteCount = 64 * 1_024 * 1_024

    private let fileManager: FileManager
    private let rootURL: URL
    private let removesRootOnDeinit: Bool

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        removesRootOnDeinit: Bool = true
    ) {
        self.fileManager = fileManager
        self.rootURL =
            rootURL
            ?? fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-session-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        self.removesRootOnDeinit = removesRootOnDeinit
    }

    static func production(
        fileManager: FileManager = .default
    ) -> BrowserExtensionPackageStore {
        let applicationSupport =
            fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        guard let applicationSupport else {
            preconditionFailure(
                "Crest requires a persistent Application Support directory."
            )
        }
        return BrowserExtensionPackageStore(
            fileManager: fileManager,
            rootURL:
                applicationSupport
                .appending(path: "Crest", directoryHint: .isDirectory)
                .appending(
                    path: "Extensions",
                    directoryHint: .isDirectory
                ),
            removesRootOnDeinit: false
        )
    }

    deinit {
        guard removesRootOnDeinit else { return }
        try? fileManager.removeItem(at: rootURL)
    }

    func stage(
        _ sourceURL: URL,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        try validate(sourceURL)
        let extensionID = BrowserExtensionUnpackedIdentityPolicy.extensionID(
            for: sourceURL,
            fileManager: fileManager
        )
        // The identity is stable but the stored copy is not: a re-import has to
        // land beside the previous copy so it can be swapped in only after the
        // new one loads. The replaced copy is reclaimed by the caller.
        let packageID = UUID().uuidString.lowercased()
        let pathExtension = sourceURL.pathExtension
        let packageName =
            pathExtension.isEmpty
            ? packageID
            : "\(packageID).\(pathExtension)"
        let destinationURL = try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: false
        )
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try fileManager.copyItem(
                at: sourceURL,
                to: destinationURL
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return BrowserExtensionPackage(
            extensionID: extensionID,
            packageName: packageName,
            resourceURL: destinationURL
        )
    }

    func stage(
        _ package: BrowserVerifiedCRX3Package,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        guard package.zipArchiveData.count <= Self.maximumArchiveByteCount else {
            throw BrowserExtensionPackageStoreError.packageTooLarge
        }
        guard package.zipArchiveData.starts(with: [0x50, 0x4b, 0x03, 0x04]) else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }
        let packageName = "\(package.extensionID.rawValue)-\(UUID().uuidString.lowercased()).zip"
        let destinationURL = try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: false
        )
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try package.zipArchiveData.write(
                to: destinationURL,
                options: [.atomic]
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return BrowserExtensionPackage(
            extensionID: package.extensionID.rawValue,
            packageName: packageName,
            resourceURL: destinationURL
        )
    }

    func stage(
        _ package: BrowserVerifiedXPIPackage,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        guard package.archiveData.count <= Self.maximumArchiveByteCount else {
            throw BrowserExtensionPackageStoreError.packageTooLarge
        }
        guard package.archiveData.starts(with: [0x50, 0x4b, 0x03, 0x04]) else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }
        let packageName =
            "\(package.extensionID.packageNameComponent)"
            + "-\(UUID().uuidString.lowercased()).zip"
        let destinationURL = try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: false
        )
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try package.archiveData.write(
                to: destinationURL,
                options: [.atomic]
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return BrowserExtensionPackage(
            extensionID: package.extensionID.rawValue,
            packageName: packageName,
            resourceURL: destinationURL
        )
    }

    func stage(
        _ package: BrowserLocalExtensionPackage,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        if case .directory(let files) = package.payload {
            return try stageDirectoryPackage(
                package,
                files: files,
                in: spaceID
            )
        }
        guard case .archive(let archiveData) = package.payload,
            package.format != .safariCustom
        else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }
        guard archiveData.count <= Self.maximumArchiveByteCount else {
            throw BrowserExtensionPackageStoreError.packageTooLarge
        }
        guard archiveData.starts(with: [0x50, 0x4b, 0x03, 0x04]) else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }
        let digest = Data(SHA256.hash(data: archiveData)).hexString
        guard digest == package.sha256Hex.lowercased() else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }

        let packageName =
            "local-\(UUID().uuidString.lowercased())-"
            + "\(package.format.filenameExtension).zip"
        let destinationURL = try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: false
        )
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try archiveData.write(
                to: destinationURL,
                options: [.atomic]
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return BrowserExtensionPackage(
            extensionID: package.extensionID,
            packageName: packageName,
            resourceURL: destinationURL
        )
    }

    private func stageDirectoryPackage(
        _ package: BrowserLocalExtensionPackage,
        files: [BrowserLocalExtensionDirectoryFile],
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        guard package.validatedSafariCustomDirectoryFiles == files
        else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }

        let packageName =
            "local-\(UUID().uuidString.lowercased())-safari-custom"
        let destinationURL = try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: false
        )
        try fileManager.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        do {
            for file in files {
                let fileURL = destinationURL.appending(
                    path: file.relativePath
                )
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try file.data.write(to: fileURL, options: [.atomic])
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return BrowserExtensionPackage(
            extensionID: package.extensionID,
            packageName: packageName,
            resourceURL: destinationURL
        )
    }

    func stageVerifiedChromeResource(
        _ sourceURL: URL,
        extensionID: BrowserChromeExtensionID,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        try validate(sourceURL)
        let pathExtension = sourceURL.pathExtension
        let suffix = UUID().uuidString.lowercased()
        let packageName =
            pathExtension.isEmpty
            ? "\(extensionID.rawValue)-\(suffix)"
            : "\(extensionID.rawValue)-\(suffix).\(pathExtension)"
        let destinationURL = try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: false
        )
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return BrowserExtensionPackage(
            extensionID: extensionID.rawValue,
            packageName: packageName,
            resourceURL: destinationURL
        )
    }

    func resourceURL(
        packageName: String,
        in spaceID: SpaceID
    ) throws -> URL {
        try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: true
        )
    }

    func discard(_ package: BrowserExtensionPackage) {
        try? fileManager.removeItem(at: package.resourceURL)
    }

    func discard(packageName: String, in spaceID: SpaceID) {
        guard
            let packageURL = try? resourceURL(
                packageName: packageName,
                in: spaceID,
                requiresExistingFile: false
            )
        else {
            return
        }
        try? fileManager.removeItem(at: packageURL)
    }

    func removePackage(
        packageName: String,
        in spaceID: SpaceID
    ) throws {
        let packageURL = try resourceURL(
            packageName: packageName,
            in: spaceID,
            requiresExistingFile: false
        )
        guard fileManager.fileExists(atPath: packageURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: packageURL)
        } catch CocoaError.fileNoSuchFile {
            // WebKit can finish releasing an unpacked extension between the
            // existence check and removal. The requested end state is already
            // satisfied, so keep extension removal idempotent.
        }
    }

    func removePackages(in spaceID: SpaceID) throws {
        let spaceDirectory = rootURL.appending(
            path: spaceID.rawValue.uuidString.lowercased(),
            directoryHint: .isDirectory
        ).standardizedFileURL
        guard spaceDirectory.deletingLastPathComponent() == rootURL.standardizedFileURL else {
            throw BrowserExtensionPackageStoreError.unsafePackageName
        }
        guard fileManager.fileExists(atPath: spaceDirectory.path) else {
            return
        }
        try fileManager.removeItem(at: spaceDirectory)
    }

    private func resourceURL(
        packageName: String,
        in spaceID: SpaceID,
        requiresExistingFile: Bool
    ) throws -> URL {
        guard isSafePackageName(packageName) else {
            throw BrowserExtensionPackageStoreError.unsafePackageName
        }
        let spaceDirectory = rootURL.appending(
            path: spaceID.rawValue.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        let candidate =
            spaceDirectory
            .appending(path: packageName)
            .standardizedFileURL
        let expectedParent = spaceDirectory.standardizedFileURL.path
        guard
            candidate.deletingLastPathComponent().path
                == expectedParent
        else {
            throw BrowserExtensionPackageStoreError.unsafePackageName
        }
        if requiresExistingFile,
            !fileManager.fileExists(atPath: candidate.path)
        {
            throw BrowserExtensionPackageStoreError.packageMissing
        }
        return candidate
    }

    private func validate(_ sourceURL: URL) throws {
        let values = try sourceURL.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ]
        )
        guard values.isSymbolicLink != true else {
            throw BrowserExtensionPackageStoreError.symbolicLink
        }
        if values.isDirectory == true {
            try validateDirectory(sourceURL)
            return
        }
        guard values.isRegularFile == true else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            throw BrowserExtensionPackageStoreError.unsupportedSource
        }
        guard values.fileSize ?? 0 <= Self.maximumArchiveByteCount else {
            throw BrowserExtensionPackageStoreError.packageTooLarge
        }
    }

    private func validateDirectory(_ sourceURL: URL) throws {
        var enumerationError: (any Error)?
        guard
            let enumerator = fileManager.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ],
                options: [],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            )
        else {
            throw BrowserExtensionPackageStoreError.unreadableSource
        }
        var entryCount = 0
        var byteCount = 0
        for case let url as URL in enumerator {
            entryCount += 1
            guard entryCount <= Self.maximumDirectoryEntryCount else {
                throw BrowserExtensionPackageStoreError.packageTooLarge
            }
            let values = try url.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard values.isSymbolicLink != true else {
                throw BrowserExtensionPackageStoreError.symbolicLink
            }
            guard
                values.isDirectory == true
                    || values.isRegularFile == true
            else {
                throw BrowserExtensionPackageStoreError
                    .unsupportedSource
            }
            if values.isRegularFile == true {
                byteCount += values.fileSize ?? 0
                guard byteCount <= Self.maximumDirectoryByteCount else {
                    throw BrowserExtensionPackageStoreError.packageTooLarge
                }
            }
        }
        if enumerationError != nil {
            throw BrowserExtensionPackageStoreError.unreadableSource
        }
    }

    private func isSafePackageName(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.utf8.count <= 255,
            value != ".",
            value != "..",
            !value.contains("/"),
            !value.contains("\\")
        else {
            return false
        }
        return URL(fileURLWithPath: value).lastPathComponent == value
    }
}
