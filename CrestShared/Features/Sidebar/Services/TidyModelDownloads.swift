import CryptoKit
import Foundation

// MARK: - Types

/// A downloaded file's SHA-256 is not the pinned one.
struct TidyModelDownloadMismatch: Error {
    let path: String
}

/// One file a Tidy method needs: where it is kept in the method's folder,
/// where it is published at a pinned revision, and the SHA-256 it must have.
struct TidyModelFile: Sendable {
    let path: String
    let address: URL
    let sha256: String
}

/// The models Tidy runs, downloaded once the person turns Tidy on and deleted
/// when they turn it off. Nothing is bundled with the app. The download is the
/// current `TidyMethod`'s public files, each checked against its SHA-256; it
/// carries nothing about the person's tabs.
@MainActor
@Observable
final class TidyModelDownloads {
    // MARK: - Static Variables

    static let shared = TidyModelDownloads()

    // MARK: - Variables

    /// The loaded models, once their files are downloaded and verified. Tidy
    /// is offered only while this is set.
    private(set) var models: (any TidyTabModels)?
    /// The method `models` belong to.
    private(set) var method: TidyMethod?
    private(set) var isDownloading = false
    /// The last download or load failed. Turning Tidy off and on again retries.
    private(set) var didFail = false
    /// Counts downloads started and Tidy turned off, so a download that Tidy
    /// was turned off during sets nothing when it finishes.
    private var syncCount = 0

    /// Where every method's files are kept: the installed app's storage, or a
    /// named isolated launch's own, as `BrowserTabStateArchive` keeps tab
    /// state. Nil for any other isolated launch, so it never reads or deletes
    /// the installed app's copy.
    private var directory: URL? {
        let environment = BrowserLaunchEnvironment.current
        guard
            var directory = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
        else { return nil }
        if environment.requiresIsolation {
            guard !environment.isXCTestRuntime, !environment.isSwiftUIPreviewRuntime,
                let identity = environment.persistentIsolationID
            else { return nil }
            directory = directory.appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(Self.sha256(of: Data(identity.utf8)), isDirectory: true)
        }
        return directory.appendingPathComponent("Tidy", isDirectory: true)
    }

    // MARK: - Actions - Keeping in step

    /// Downloads and loads the current method's models while Tidy is on, and
    /// deletes every method's files when Tidy is off. Files of a method this
    /// device no longer runs are deleted too. Safe to call repeatedly; files
    /// already verified are reused.
    func sync(isTidyEnabled: Bool) async {
        guard isTidyEnabled else {
            syncCount += 1
            models = nil
            method = nil
            didFail = false
            isDownloading = false
            if let directory { try? FileManager.default.removeItem(at: directory) }
            return
        }
        let current = TidyMethod.current
        guard models == nil || method != current, !isDownloading, let directory else { return }
        syncCount += 1
        let call = syncCount
        models = nil
        method = current
        isDownloading = true
        defer { if call == syncCount { isDownloading = false } }
        do {
            let folder = directory.appendingPathComponent(current.directoryName, isDirectory: true)
            Self.removeEverything(in: directory, except: folder)
            for file in current.files {
                try await Self.verifyFile(file, in: folder)
            }
            let loaded = try await current.load(folder)
            guard call == syncCount else { return }
            models = loaded
            didFail = false
        } catch {
            guard call == syncCount else { return }
            didFail = true
            DiagnosticLog.tidy.error("Tidy couldn't get its models: \(DiagnosticLog.describe(error))")
        }
    }

    private nonisolated static func removeEverything(in directory: URL, except kept: URL) {
        let contents =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in contents where item.lastPathComponent != kept.lastPathComponent {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Makes sure `folder` holds `file` with its pinned SHA-256, downloading
    /// it when the copy is missing or differs.
    private nonisolated static func verifyFile(_ file: TidyModelFile, in folder: URL) async throws {
        let destination = folder.appendingPathComponent(file.path)
        if let existing = try? Data(contentsOf: destination, options: .alwaysMapped),
            sha256(of: existing) == file.sha256
        {
            return
        }
        let (downloaded, _) = try await URLSession.shared.download(from: file.address)
        guard sha256(of: try Data(contentsOf: downloaded, options: .alwaysMapped)) == file.sha256 else {
            try? FileManager.default.removeItem(at: downloaded)
            throw TidyModelDownloadMismatch(path: file.path)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded, to: destination)
    }

    private nonisolated static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
