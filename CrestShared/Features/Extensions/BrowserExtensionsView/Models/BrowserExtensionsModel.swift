import Foundation
import Observation

@Observable
@MainActor
final class BrowserExtensionsModel {
    let space: BrowserSpace
    let extensionControllerPool: BrowserExtensionControllerPool

    var isChoosingExtension = false
    private(set) var isLoadingExtension = false
    private(set) var operationExtensionID: String?
    private(set) var operationFailure: BrowserExtensionOperationFailure?
    private(set) var pendingRemoval: BrowserExtensionSummary?

    var extensions: [BrowserExtensionSummary] {
        extensionControllerPool.extensions(in: space.id)
    }

    init(
        space: BrowserSpace,
        extensionControllerPool: BrowserExtensionControllerPool
    ) {
        self.space = space
        self.extensionControllerPool = extensionControllerPool
    }

    func importExtension(from result: Result<[URL], any Error>) async {
        do {
            guard let sourceURL = try result.get().first else { return }
            isLoadingExtension = true
            defer { isLoadingExtension = false }

            let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            try await extensionControllerPool.loadUnpackedExtension(
                from: sourceURL,
                in: space
            )
        } catch {
            publishFailure(error)
        }
    }

    func setEnabled(
        _ enabled: Bool,
        extensionSummary: BrowserExtensionSummary
    ) async {
        await performOperation(for: extensionSummary.id) {
            try await extensionControllerPool.setExtensionEnabled(
                enabled,
                extensionID: extensionSummary.id,
                in: space
            )
        }
    }

    func setPermissionDecision(
        _ decision: BrowserExtensionAccessDecision,
        for permission: String,
        extensionSummary: BrowserExtensionSummary
    ) async {
        await performOperation(for: extensionSummary.id) {
            try await extensionControllerPool.setPermissionDecision(
                decision,
                for: permission,
                extensionID: extensionSummary.id,
                in: space
            )
        }
    }

    func setHostDecision(
        _ decision: BrowserExtensionAccessDecision,
        for hostPattern: String,
        extensionSummary: BrowserExtensionSummary
    ) async {
        await performOperation(for: extensionSummary.id) {
            try await extensionControllerPool.setHostDecision(
                decision,
                for: hostPattern,
                extensionID: extensionSummary.id,
                in: space
            )
        }
    }

    func requestRemoval(of extensionSummary: BrowserExtensionSummary) {
        pendingRemoval = extensionSummary
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    func remove(_ extensionSummary: BrowserExtensionSummary) async {
        guard operationExtensionID == nil else { return }
        pendingRemoval = nil
        operationExtensionID = extensionSummary.id
        defer { operationExtensionID = nil }

        do {
            try await extensionControllerPool.removeExtension(
                extensionID: extensionSummary.id,
                from: space
            )
        } catch {
            publishFailure(error)
        }
    }

    func clearOperationFailure() {
        operationFailure = nil
    }

    private func performOperation(
        for extensionID: String,
        _ operation: @MainActor () async throws -> Void
    ) async {
        guard operationExtensionID == nil else { return }
        operationExtensionID = extensionID
        defer { operationExtensionID = nil }

        do {
            try await operation()
        } catch {
            publishFailure(error)
        }
    }

    private func publishFailure(_ error: any Error) {
        operationFailure = BrowserExtensionOperationFailure(
            message: error.localizedDescription
        )
    }
}
