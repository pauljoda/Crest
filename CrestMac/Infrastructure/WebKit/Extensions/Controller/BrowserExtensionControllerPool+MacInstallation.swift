import Foundation

extension BrowserExtensionControllerPool {
    @discardableResult
    func installSafariWebExtension(
        _ candidate: BrowserSafariWebExtensionCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let summary = try await installationController.installSafariWebExtension(
            candidate,
            in: space
        )
        try await finishAdditionalInstallations(
            summary: summary, in: space.id, destinations: candidate.accessReview.additionalSpaceIDs)
        return summary
    }

    @discardableResult
    func installChromeWebStoreExtension(
        _ candidate: BrowserChromeWebStoreCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let summary = try await installationController.installChromeWebStoreExtension(
            candidate,
            in: space
        )
        try await finishAdditionalInstallations(
            summary: summary, in: space.id, destinations: candidate.accessReview.additionalSpaceIDs)
        return summary
    }

    @discardableResult
    func installMozillaAddonsExtension(
        _ candidate: BrowserMozillaAddonsCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let summary = try await installationController.installMozillaAddonsExtension(
            candidate,
            in: space
        )
        try await finishAdditionalInstallations(
            summary: summary, in: space.id, destinations: candidate.accessReview.additionalSpaceIDs)
        return summary
    }

    @discardableResult
    func installLocalExtension(
        _ candidate: BrowserLocalExtensionCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let summary = try await installationController.installLocalExtension(
            candidate,
            in: space
        )
        try await finishAdditionalInstallations(
            summary: summary, in: space.id, destinations: candidate.accessReview.additionalSpaceIDs)
        return summary
    }

    private func finishAdditionalInstallations(
        summary: BrowserExtensionSummary, in source: SpaceID, destinations: Set<SpaceID>
    ) async throws {
        do {
            try await copyExtension(extensionID: summary.id, from: source, to: destinations)
        } catch {
            let completedCount = destinations.filter {
                $0 != source && persistenceController.installation(extensionID: summary.id, in: $0) != nil
            }.count
            throw BrowserExtensionPartialInstallationError(
                summary: summary, additionalSpaceCount: completedCount, copyFailure: error.localizedDescription)
        }
    }

}
