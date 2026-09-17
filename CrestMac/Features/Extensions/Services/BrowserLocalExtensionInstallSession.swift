import Foundation
import Observation

@Observable
@MainActor
final class BrowserLocalExtensionInstallSession {
    let space: BrowserSpace

    var isChoosingPackage = false
    var isPresented = false
    private(set) var isInstalling = false
    private(set) var installedAdditionalSpaceCount = 0
    private(set) var installedCopyWarnings: [String] = []
    private(set) var phase: BrowserLocalExtensionInstallPhase = .unavailable

    @ObservationIgnored private let extensionControllerPool: BrowserExtensionControllerPool
    @ObservationIgnored private let provider: BrowserLocalExtensionProvider

    init(
        space: BrowserSpace,
        extensionControllerPool: BrowserExtensionControllerPool,
        provider: BrowserLocalExtensionProvider = BrowserLocalExtensionProvider()
    ) {
        self.space = space
        self.extensionControllerPool = extensionControllerPool
        self.provider = provider
    }

    var additionalSpaces: [BrowserSpace] {
        guard let candidate = phase.candidate else { return [] }
        return extensionControllerPool.copyDestinations(extensionID: candidate.id, excluding: space.id)
    }

    var isBusy: Bool {
        isPreparing || isInstalling
    }

    var isPreparing: Bool {
        if case .preparing = phase { return true }
        return false
    }

    func choosePackage() {
        guard !isBusy else { return }
        isChoosingPackage = true
    }

    func prepare(
        from result: Result<[URL], any Error>
    ) async {
        do {
            guard let sourceURL = try result.get().first else { return }
            phase = .preparing
            isPresented = true

            let hasSecurityScope =
                sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            var candidate = try await provider.candidate(for: sourceURL)
            let previous = extensionControllerPool.persistenceController.installation(
                extensionID: candidate.id, in: space.id)
            candidate.replacingDisplayName = previous?.displayName
            if BrowserExtensionInstallationSource.localPackage(candidate.source).authenticatesContinuity(
                from: previous?.source)
            {
                candidate.accessReview.previousSnapshot = previous?.permissionSnapshot
            }
            phase = .review(candidate: candidate, errorDescription: nil)
        } catch {
            phase = .failed(errorDescription: error.localizedDescription)
            isPresented = true
        }
    }

    func install(review: BrowserExtensionInstallationPermissionPolicy.Review = .init()) {
        guard case .review(var candidate, _) = phase,
            !isInstalling
        else {
            return
        }
        candidate.accessReview = review
        phase = .review(candidate: candidate, errorDescription: nil)
        isInstalling = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completion = try await BrowserExtensionInstallationCompletion.perform(
                    additionalSpaceCount: review.additionalSpaceIDs.count
                ) { try await extensionControllerPool.installLocalExtension(candidate, in: space) }
                let summary = completion.summary
                installedAdditionalSpaceCount = completion.additionalSpaceCount
                installedCopyWarnings = completion.copyWarnings
                isInstalling = false
                phase = .installed(
                    name: summary.displayName,
                    compatibilityIssues: candidate.compatibility.issues
                        .map(\.message)
                )
            } catch is CancellationError {
                isInstalling = false
            } catch {
                isInstalling = false
                phase = .review(
                    candidate: candidate,
                    errorDescription: error.localizedDescription
                )
            }
        }
    }

    func dismiss() {
        guard !isBusy else { return }
        isPresented = false
        phase = .unavailable
    }

    func chooseAnotherPackage() {
        guard !isBusy else { return }
        isPresented = false
        phase = .unavailable
        DispatchQueue.main.async { [weak self] in
            self?.isChoosingPackage = true
        }
    }
}
