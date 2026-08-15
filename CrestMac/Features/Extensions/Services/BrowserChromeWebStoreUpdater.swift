import Foundation

/// Replaces a Chrome Web Store installation with the store's current package.
///
/// Every replacement takes the ordinary installation path — the same download
/// endpoint, the same CRX3 verification against the pinned publisher key, the
/// same identity cross-checks, and the same rollback on failure. Nothing here
/// is a shortcut for "we already trust this one".
///
/// In particular, the store's own `codebase` URL from an update-check answer
/// is never followed. Crest re-derives the download from the extension ID it
/// already trusts, so a tampered update-check document cannot redirect a
/// replacement at an attacker's package.
@MainActor
final class BrowserChromeWebStoreUpdater: BrowserExtensionUpdateApplying {
    private weak var pool: BrowserExtensionControllerPool?
    private let provider: BrowserChromeWebStoreProvider
    private let spaces: @MainActor () -> [BrowserSpace]

    init(
        pool: BrowserExtensionControllerPool,
        provider: BrowserChromeWebStoreProvider = BrowserChromeWebStoreProvider(),
        spaces: @escaping @MainActor () -> [BrowserSpace]
    ) {
        self.pool = pool
        self.provider = provider
        self.spaces = spaces
    }

    func chromeWebStoreUpdateTargets() -> [BrowserExtensionUpdateTarget] {
        pool?.chromeWebStoreUpdateTargets() ?? []
    }

    func applyUpdate(
        to target: BrowserExtensionUpdateTarget
    ) async throws -> String? {
        guard let pool else {
            throw BrowserChromeWebStoreUpdaterError.unavailableRuntime
        }
        guard
            let space = spaces().first(where: { $0.id == target.spaceID })
        else {
            throw BrowserChromeWebStoreUpdaterError.missingSpace
        }
        guard
            let installation = pool.persistenceController.installation(
                extensionID: target.extensionID,
                in: target.spaceID
            )
        else {
            throw BrowserChromeWebStoreUpdaterError.missingInstallation
        }
        guard case .chromeWebStore(let source) = installation.source,
            source.extensionID.rawValue == target.extensionID,
            let item = BrowserChromeWebStoreItem(url: source.storeURL),
            item.id == source.extensionID
        else {
            throw BrowserChromeWebStoreUpdaterError.unverifiableSource
        }

        let candidate = try await provider.candidate(for: item)
        guard candidate.source.extensionID == source.extensionID,
            candidate.verifiedPackage.extensionID == source.extensionID,
            candidate.source.publisherKeyHashHex
                == source.publisherKeyHashHex
        else {
            throw BrowserChromeWebStoreUpdaterError.identityMismatch
        }
        let summary = try await pool.installChromeWebStoreExtension(
            candidate,
            in: space
        )
        return summary.version
    }
}
