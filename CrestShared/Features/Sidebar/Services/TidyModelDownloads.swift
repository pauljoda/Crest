import CryptoKit
import Foundation

// MARK: - Types

/// A downloaded file's SHA-256 is not the pinned one.
struct TidyModelDownloadMismatch: Error {
    let fileName: String
}

/// One file of the word-vector table: where it is published, at a pinned
/// revision, and the SHA-256 it must have.
struct TidyModelFile: Sendable {
    let fileName: String
    let address: URL
    let sha256: String
}

/// The word-vector table Tidy groups tabs with, downloaded once the person
/// turns Tidy on and deleted when they turn it off. Nothing is bundled with the
/// app. The download is two public files from a pinned Hugging Face revision,
/// each checked against its SHA-256; it carries nothing about the person's tabs.
@MainActor
@Observable
final class TidyModelDownloads {
    // MARK: - Static Variables

    static let shared = TidyModelDownloads()

    /// potion-base-8M by Minish Lab, MIT licensed, at revision `bf8b056`.
    private static let revision = "bf8b056651a2c21b8d2565580b8569da283cab23"
    private static let vocabulary = TidyModelFile(
        fileName: "vocab.txt",
        address: URL(string: "https://huggingface.co/minishlab/potion-base-8M/resolve/\(revision)/vocab.txt")!,
        sha256: "1394523a67ddd404a825428018c0582a6998bcfa044ecbcbf1f4d71adb94c61c")
    private static let matrix = TidyModelFile(
        fileName: "model.safetensors",
        address: URL(string: "https://huggingface.co/minishlab/potion-base-8M/resolve/\(revision)/model.safetensors")!,
        sha256: "f65d0f325faadc1e121c319e2faa41170d3fa07d8c89abd48ca5358d9a223de2")

    // MARK: - Variables

    /// The loaded table, once its files are downloaded and verified. Tidy is
    /// offered only while this is set.
    private(set) var embedder: TidyTabEmbedder?
    private(set) var isDownloading = false
    /// The last download or load failed. Turning Tidy off and on again retries.
    private(set) var didFail = false
    /// Counts downloads started and Tidy turned off, so a download that Tidy
    /// was turned off during sets nothing when it finishes.
    private var syncCount = 0

    /// Where the table is kept: the installed app's storage, or a named
    /// isolated launch's own, as `BrowserTabStateArchive` keeps tab state.
    /// Nil for any other isolated launch, so it never reads or deletes the
    /// installed app's copy.
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

    /// Downloads and loads the table while Tidy is on, and deletes it when Tidy
    /// is off. Safe to call repeatedly; files already verified are reused.
    func sync(isTidyEnabled: Bool) async {
        guard isTidyEnabled else {
            syncCount += 1
            embedder = nil
            didFail = false
            isDownloading = false
            if let directory { try? FileManager.default.removeItem(at: directory) }
            return
        }
        guard embedder == nil, !isDownloading, let directory else { return }
        syncCount += 1
        let call = syncCount
        isDownloading = true
        defer { if call == syncCount { isDownloading = false } }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let vocabularyURL = try await Self.verifiedFile(Self.vocabulary, in: directory)
            let matrixURL = try await Self.verifiedFile(Self.matrix, in: directory)
            let loaded = try await Task.detached(priority: .utility) {
                try TidyTabEmbedder(vocabularyURL: vocabularyURL, matrixURL: matrixURL)
            }.value
            guard call == syncCount else { return }
            embedder = loaded
            didFail = false
        } catch {
            guard call == syncCount else { return }
            didFail = true
            DiagnosticLog.tidy.error("Tidy couldn't get its word table: \(DiagnosticLog.describe(error))")
        }
    }

    /// The local copy of `file`, downloading it when the copy is missing or no
    /// longer has the pinned SHA-256.
    private nonisolated static func verifiedFile(_ file: TidyModelFile, in directory: URL) async throws -> URL {
        let destination = directory.appendingPathComponent(file.fileName)
        if let existing = try? Data(contentsOf: destination, options: .alwaysMapped),
            sha256(of: existing) == file.sha256
        {
            return destination
        }
        let (downloaded, _) = try await URLSession.shared.download(from: file.address)
        guard sha256(of: try Data(contentsOf: downloaded, options: .alwaysMapped)) == file.sha256 else {
            try? FileManager.default.removeItem(at: downloaded)
            throw TidyModelDownloadMismatch(fileName: file.fileName)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded, to: destination)
        return destination
    }

    private nonisolated static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
