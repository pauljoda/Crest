import Foundation

/// Drives one add-on installation from the moment an AMO page asks for it until
/// the review sheet is dismissed.
///
/// The flow owns its own state instead of spreading it across the page: a page
/// already carries a large surface, and every value here — the item, the
/// prepared candidate, and the phase flags derived from them — is meaningful
/// only while this sheet is up.
@MainActor
@Observable
final class BrowserMozillaAddonsInstallSession {
    typealias Prepare =
        @MainActor (BrowserMozillaAddonsItem) async throws ->
        BrowserMozillaAddonsCandidate
    typealias Install =
        @MainActor (BrowserMozillaAddonsCandidate) async throws ->
        BrowserExtensionSummary
    typealias ReportInstalled =
        @MainActor (BrowserMozillaAddonSlug) async -> Void

    private(set) var item: BrowserMozillaAddonsItem?
    private(set) var candidate: BrowserMozillaAddonsCandidate?
    private(set) var isPreparing = false
    private(set) var isInstalling = false
    private(set) var errorDescription: String?
    private(set) var installedExtensionName: String?
    private(set) var installedCompatibilityIssues: [String] = []

    let spaceID: SpaceID
    let spaceName: String

    @ObservationIgnored private let prepare: Prepare
    @ObservationIgnored private let install: Install
    @ObservationIgnored var reportInstalled: ReportInstalled = { _ in }
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        spaceID: SpaceID,
        spaceName: String,
        prepare: @escaping Prepare = { _ in
            throw BrowserExtensionControllerPoolError
                .unsupportedInstallationSource
        },
        install: @escaping Install = { _ in
            throw BrowserExtensionControllerPoolError
                .unsupportedInstallationSource
        }
    ) {
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.prepare = prepare
        self.install = install
    }

    var isPresented: Bool { item != nil }

    var phase: BrowserMozillaAddonsInstallPhase {
        BrowserMozillaAddonsInstallPhase.resolve(
            isPreparing: isPreparing,
            installedName: installedExtensionName,
            candidate: candidate,
            errorDescription: errorDescription
        )
    }

    func begin(for item: BrowserMozillaAddonsItem) {
        task?.cancel()
        self.item = item
        candidate = nil
        installedExtensionName = nil
        installedCompatibilityIssues = []
        errorDescription = nil
        isInstalling = false
        isPreparing = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let prepared = try await prepare(item)
                guard !Task.isCancelled,
                    self.item?.slug == prepared.item.slug
                else {
                    return
                }
                candidate = prepared
                isPreparing = false
            } catch is CancellationError {
                isPreparing = false
            } catch {
                isPreparing = false
                errorDescription = error.localizedDescription
            }
        }
    }

    func installPrepared() {
        guard let candidate, !isInstalling else { return }
        errorDescription = nil
        isInstalling = true
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let summary = try await install(candidate)
                guard !Task.isCancelled else { return }
                isInstalling = false
                installedExtensionName = summary.displayName
                installedCompatibilityIssues = candidate
                    .compatibility.issues.map(\.message)
                self.candidate = nil
                await reportInstalled(candidate.source.slug)
            } catch is CancellationError {
                isInstalling = false
            } catch {
                isInstalling = false
                errorDescription = error.localizedDescription
            }
        }
    }

    func retryPreparation() {
        guard let item, !isInstalling else { return }
        begin(for: item)
    }

    func dismiss() {
        guard !isInstalling else { return }
        cancel()
        item = nil
        candidate = nil
        installedCompatibilityIssues = []
        isPreparing = false
        errorDescription = nil
        installedExtensionName = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
