import CryptoKit
import Foundation

// MARK: - Types

/// A downloaded file's SHA-256 is not the pinned one, or the server did not
/// answer with the file.
struct TidyWordTableDownloadFailed: Error {
    let fileName: String
}

/// One file of the word-vector table: where it is published, at a pinned
/// revision, and the SHA-256 it must have.
struct TidyWordTableFile: Sendable {
    let fileName: String
    let address: URL
    let sha256: String
}

/// The word-vector table Tidy groups tabs with, downloaded once the person
/// turns Tidy on and deleted when they turn it off. Nothing is bundled with
/// the app. The download is two public files from a pinned Hugging Face
/// revision, each checked against its SHA-256, fetched without cookies, a
/// cache or credentials; it carries nothing about the person's tabs.
@MainActor
@Observable
final class TidyWordTable {
    // MARK: - Static Variables

    /// potion-base-8M by Minish Lab, MIT licensed, at revision `bf8b056`.
    private static let revision = "bf8b056651a2c21b8d2565580b8569da283cab23"
    private static let vocabulary = TidyWordTableFile(
        fileName: "vocab.txt",
        address: URL(string: "https://huggingface.co/minishlab/potion-base-8M/resolve/\(revision)/vocab.txt")!,
        sha256: "1394523a67ddd404a825428018c0582a6998bcfa044ecbcbf1f4d71adb94c61c")
    private static let matrix = TidyWordTableFile(
        fileName: "model.safetensors",
        address: URL(string: "https://huggingface.co/minishlab/potion-base-8M/resolve/\(revision)/model.safetensors")!,
        sha256: "f65d0f325faadc1e121c319e2faa41170d3fa07d8c89abd48ca5358d9a223de2")

    /// A session that keeps nothing: no cookies, cache or credentials.
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    // MARK: - Variables

    /// The loaded table, once its files are downloaded and verified. Tidy is
    /// offered only while this is set.
    private(set) var embedder: TidyTabEmbedder?
    private(set) var isDownloading = false
    /// The last download or load failed. Turning Tidy off and on again retries.
    private(set) var didFail = false
    /// The download or load under way, which removing the table cancels.
    private var loading: Task<Void, Never>?
    /// Counts loads started and removals, so a load that a removal overtook
    /// sets nothing when it finishes.
    private var generation = 0

    /// Where the table is kept: the installed app's storage, or a named
    /// isolated launch's own, as `BrowserTabStateArchive` keeps tab state.
    /// Nil for any other isolated launch, so it never reads or deletes the
    /// installed app's copy.
    private let directory: URL?

    // MARK: - Initializers

    init(environment: BrowserLaunchEnvironment = .current) {
        directory = Self.storageDirectory(for: environment)
    }

    private static func storageDirectory(for environment: BrowserLaunchEnvironment) -> URL? {
        guard
            var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
        else { return nil }
        if environment.requiresIsolation {
            guard !environment.isXCTestRuntime, !environment.isSwiftUIPreviewRuntime,
                let identity = environment.persistentIsolationID
            else { return nil }
            directory = directory.appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(sha256(of: Data(identity.utf8)), isDirectory: true)
        }
        return directory.appendingPathComponent("Tidy", isDirectory: true)
    }

    // MARK: - Actions - Keeping in step

    /// Downloads the table's files when they are missing or changed, and loads
    /// them. Does nothing while the table is loaded or loading.
    func load() {
        guard embedder == nil, loading == nil, let directory else { return }
        generation += 1
        let started = generation
        isDownloading = true
        didFail = false
        loading = Task { [weak self] in
            let result: Result<TidyTabEmbedder, any Error>
            do {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let vocabularyURL = try await Self.verifiedFile(Self.vocabulary, in: directory)
                let matrixURL = try await Self.verifiedFile(Self.matrix, in: directory)
                result = .success(
                    try await Task.detached(priority: .utility) {
                        try TidyTabEmbedder(vocabularyURL: vocabularyURL, matrixURL: matrixURL)
                    }.value)
            } catch {
                result = .failure(error)
            }
            self?.finishLoading(started, with: result)
        }
    }

    private func finishLoading(_ started: Int, with result: Result<TidyTabEmbedder, any Error>) {
        guard started == generation else { return }
        loading = nil
        isDownloading = false
        switch result {
        case .success(let loaded):
            embedder = loaded
        case .failure(let error):
            didFail = true
            DiagnosticLog.tidy.error("Tidy couldn't get its word table: \(DiagnosticLog.describe(error))")
        }
    }

    /// Stops any download and deletes the table's files.
    func remove() {
        generation += 1
        loading?.cancel()
        loading = nil
        embedder = nil
        isDownloading = false
        didFail = false
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - Actions - Downloading

    /// The local copy of `file`, downloading it when the copy is missing or no
    /// longer has the pinned SHA-256.
    private nonisolated static func verifiedFile(_ file: TidyWordTableFile, in directory: URL) async throws -> URL {
        let destination = directory.appendingPathComponent(file.fileName)
        if let existing = try? Data(contentsOf: destination, options: .alwaysMapped),
            sha256(of: existing) == file.sha256
        {
            return destination
        }
        let (downloaded, response) = try await session.download(from: file.address)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            sha256(of: try Data(contentsOf: downloaded, options: .alwaysMapped)) == file.sha256
        else { throw TidyWordTableDownloadFailed(fileName: file.fileName) }
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded, to: destination)
        return destination
    }

    private nonisolated static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
