import Foundation

@MainActor
final class BrowserExtensionRestorationController {
    private let persistence: BrowserExtensionPersistenceController
    private let runtime: BrowserExtensionRuntimeContextController

    init(
        persistence: BrowserExtensionPersistenceController,
        runtime: BrowserExtensionRuntimeContextController
    ) {
        self.persistence = persistence
        self.runtime = runtime
    }

    func restoreEnabledExtensions(in spaces: [BrowserSpace]) async {
        var spacesByID: [SpaceID: BrowserSpace] = [:]
        for space in spaces {
            spacesByID[space.id] = space
            persistence.replaceSummaries(
                in: space.id,
                nativeMessagingCapability: runtime.nativeMessagingCapability
            )
        }

        let installations = persistence.installations
        BrowserExtensionStartupLog.began(
            spaceCount: spaces.count,
            installationCount: installations.count
        )
        var enabled = 0
        var loaded = 0
        var skippedMissingSpace = 0
        var failed = 0
        var backgroundWarmUps:
            [(
                extensionID: String,
                task: Task<BrowserExtensionBackgroundWarmUp.Outcome, Never>
            )] = []

        for installation in installations {
            guard installation.isEnabled else {
                BrowserExtensionStartupLog.skippedDisabled(
                    extensionID: installation.id
                )
                continue
            }
            enabled += 1
            guard let space = spacesByID[installation.spaceID] else {
                // A record filed under a Space this session does not carry.
                // Reported rather than dropped: this is how an entire extension
                // set can disappear without one line of evidence.
                skippedMissingSpace += 1
                BrowserExtensionStartupLog.skippedMissingSpace(
                    extensionID: installation.id,
                    spaceID: installation.spaceID
                )
                continue
            }
            do {
                let context = try await runtime.loadInstallation(
                    installation,
                    in: space
                )
                if context.webExtension.hasBackgroundContent {
                    backgroundWarmUps.append(
                        (
                            extensionID: installation.id,
                            task: Task { @MainActor [runtime] in
                                await runtime
                                    .prepareBackgroundForInitialContentScriptTraffic(
                                        context
                                    )
                            }
                        )
                    )
                }
                loaded += 1
                BrowserExtensionStartupLog.loaded(
                    extensionID: installation.id,
                    spaceID: installation.spaceID
                )
            } catch {
                failed += 1
                BrowserExtensionStartupLog.failed(
                    extensionID: installation.id,
                    error: error
                )
                persistence.recordRestoreFailure(
                    error,
                    installation: installation,
                    nativeMessagingCapability:
                        runtime.nativeMessagingCapability
                )
            }
        }

        for warmUp in backgroundWarmUps {
            switch await warmUp.task.value {
            case .loaded:
                BrowserExtensionStartupLog.backgroundReady(
                    extensionID: warmUp.extensionID
                )
            case .failed(let error):
                BrowserExtensionStartupLog.backgroundFailed(
                    extensionID: warmUp.extensionID,
                    error: error
                )
            case .timedOut:
                BrowserExtensionStartupLog.backgroundTimedOut(
                    extensionID: warmUp.extensionID
                )
            }
        }

        BrowserExtensionStartupLog.finished(
            installationCount: installations.count,
            enabled: enabled,
            loaded: loaded,
            skippedMissingSpace: skippedMissingSpace,
            failed: failed
        )
    }

    func setExtensionEnabled(
        _ enabled: Bool,
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        guard
            var installation = persistence.installation(
                extensionID: extensionID,
                in: space.id
            )
        else {
            throw BrowserExtensionControllerPoolError.missingInstallation
        }
        if enabled {
            persistence.setEnabled(
                true,
                extensionID: extensionID,
                in: space.id
            )
            installation.isEnabled = true
            do {
                let context = try await runtime.loadInstallation(
                    installation,
                    in: space
                )
                _ =
                    await runtime
                    .prepareBackgroundForInitialContentScriptTraffic(context)
            } catch {
                persistence.recordRestoreFailure(
                    error,
                    installation: installation,
                    nativeMessagingCapability:
                        runtime.nativeMessagingCapability
                )
                throw error
            }
            return
        }

        if let context = runtime.loadedContext(
            extensionID: extensionID,
            in: space.id
        ) {
            runtime.persistPermissionState(
                extensionID: extensionID,
                in: space.id
            )
            try runtime.controller(for: space).unload(context)
            runtime.releaseContext(extensionID: extensionID, in: space.id)
        }
        persistence.setEnabled(
            false,
            extensionID: extensionID,
            in: space.id
        )
        guard
            let updated = persistence.installation(
                extensionID: extensionID,
                in: space.id
            )
        else {
            return
        }
        persistence.updateSummary(
            persistence.summary(
                for: updated,
                nativeMessagingCapability: runtime.nativeMessagingCapability
            ),
            in: space.id
        )
    }

    /// Permission-gated WebExtension namespaces are established when WebKit
    /// starts an extension background. Changing a grant on the live context
    /// persists the choice, but code that already tested for the namespace
    /// does not rerun. Restarting only the affected extension gives it the
    /// same permission-complete launch it will receive on the next app start.
    func restartEnabledExtension(
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: space.id
            )
        else {
            throw BrowserExtensionControllerPoolError.missingInstallation
        }
        guard installation.isEnabled else { return }

        if let context = runtime.loadedContext(
            extensionID: extensionID,
            in: space.id
        ) {
            try runtime.controller(for: space).unload(context)
            runtime.releaseContext(extensionID: extensionID, in: space.id)
        }

        do {
            let context = try await runtime.loadInstallation(
                installation,
                in: space
            )
            _ =
                await runtime
                .prepareBackgroundForInitialContentScriptTraffic(context)
        } catch {
            persistence.recordRestoreFailure(
                error,
                installation: installation,
                nativeMessagingCapability: runtime.nativeMessagingCapability
            )
            throw error
        }
    }
}
