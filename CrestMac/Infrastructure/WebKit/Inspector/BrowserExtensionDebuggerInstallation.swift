import Foundation
import WebKit

/// Assembles the `chrome.debugger` session store against the live browser and
/// installs it on an extension controller pool.
///
/// Everything that decides whether an attachment may exist lives here, because
/// only the shell can see all of it at once: the user's managed decision, the
/// Space's lock, the browsing mode, the tab's URL, and the package's host
/// access. The store itself owns transport and exclusivity and asks these
/// questions again on every command, so a decision that changes mid-session
/// ends the session rather than being remembered from attach time.
@MainActor
enum BrowserExtensionDebuggerInstallation {
    static let permissionName = "debugger"

    @discardableResult
    static func install(
        pool: BrowserExtensionControllerPool,
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        prompt: @escaping @MainActor (String) async -> Bool = {
            await BrowserExtensionDebuggerConsentPrompt.present(extensionName: $0)
        }
    ) -> BrowserExtensionDebuggerSessionStore {
        let store = BrowserExtensionDebuggerSessionStore(
            authorizeClient: { [weak pool] client in
                guard let pool, let identity = pool.debuggerIdentity(for: client) else { return false }
                return decision(pool: pool, identity: identity) == .allow
            },
            resolveTarget: { [weak pool, weak browser, weak spaceAccess] target in
                targetAccess(target, pool: pool, browser: browser, spaceAccess: spaceAccess)
            }
        )
        // Page.close, Page.bringToFront and Target.closeTarget go through the
        // same tab paths the `tabs` API uses, never through the engine protocol.
        store.tabHost = BrowserExtensionDebuggerTabCoordinatorHost(coordinator: pool.tabWindowCoordinator)
        pool.setDebuggerService(store) { [weak pool] identity in
            await consent(pool: pool, identity: identity, prompt: prompt)
        }
        // A revoked grant must end a live session at once, not at the next
        // command: the extension is holding an open Inspector connection.
        pool.permissionController.browserManagedPermissionsDidChange = { [weak store] _ in
            store?.reconcileTargets()
        }
        // Locking a Space withdraws the pages it contains for the same reason.
        spaceAccess.accessDidChange = { [weak store] in
            store?.reconcileTargets()
        }
        return store
    }

    private static func decision(
        pool: BrowserExtensionControllerPool, identity: BrowserExtensionDebuggerIdentity
    ) -> BrowserExtensionAccessDecision {
        pool.permissionDecision(
            for: permissionName, extensionID: identity.extensionID, in: identity.spaceID)
    }

    private static func consent(
        pool: BrowserExtensionControllerPool?, identity: BrowserExtensionDebuggerIdentity,
        prompt: @MainActor (String) async -> Bool
    ) async -> Bool {
        guard let pool else { return false }
        switch decision(pool: pool, identity: identity) {
        case .allow: return true
        case .block: return false
        case .ask:
            let allowed = await prompt(identity.displayName)
            pool.setPermissionDecision(
                allowed ? .allow : .block, for: permissionName, extensionID: identity.extensionID,
                in: identity.spaceID)
            return allowed
        }
    }

    /// Resolves a bound target to a page, or to why it cannot be reached.
    ///
    /// `.restricted` and `.closed` are not interchangeable: the store reports a
    /// restricted target as a refusal the extension can see and a closed one as
    /// `target_closed`, so a locked Space must not look like a closed tab.
    private static func targetAccess(
        _ target: BrowserExtensionDebuggerTarget,
        pool: BrowserExtensionControllerPool?,
        browser: BrowserStore?,
        spaceAccess: BrowserSpaceAccessController?
    ) -> BrowserExtensionDebuggerTargetAccess {
        guard let pool, let browser, !browser.isPrivateBrowsing,
            let space = browser.session.space(id: target.spaceID)
        else { return .closed }
        guard spaceAccess?.isLocked(space) != true else { return .restricted }
        guard let identity = pool.debuggerIdentity(forTarget: target) else { return .restricted }
        let coordinator = pool.tabWindowCoordinator
        guard let tab = coordinator.currentState?.space(target.spaceID)?.tab(target.tabID),
            let adapter = coordinator.tab(for: target.tabID, in: target.spaceID)
        else { return .closed }
        guard
            BrowserExtensionDebuggerTargetPolicy.allowsAttachment(
                to: tab.url, extensionBaseURL: identity.baseURL),
            let url = tab.url,
            let context = pool.loadedContext(extensionID: identity.extensionID, in: identity.spaceID),
            // Host access, not `tabs`. Reading a tab's metadata is not a claim
            // on the ability to evaluate expressions inside its page.
            context.hasAccess(to: url, in: adapter)
        else { return .restricted }
        guard let page = coordinator.pageProvider?.extensionWebView(for: target.tabID, in: target.spaceID)
        else { return .closed }
        return .available(page)
    }
}
