import Foundation

/// The app-side seam for `chrome.tabGroups`, `tabs.group`, and `tabs.ungroup`.
///
/// Registration is per extension so a watch port can find its Space and be
/// torn down with its context. The *state* behind the port is not per
/// extension: every client registered in a Space reads and writes the same
/// registry, which is what makes Chrome's browser-wide group semantics true
/// here rather than approximated per package.
@MainActor
protocol BrowserExtensionTabGroupHandling: AnyObject {
    var revision: Int { get }
    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID)
    func unregister(client: BrowserExtensionServiceClientID)
    func space(for client: BrowserExtensionServiceClientID) -> SpaceID?

    func groups(in spaceID: SpaceID) -> [BrowserExtensionTabGroup]
    func group(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID) throws
        -> BrowserExtensionTabGroup
    func membership(in spaceID: SpaceID) -> [TabID: BrowserExtensionTabGroupID]

    @discardableResult
    func group(
        _ tabs: [TabID], in spaceID: SpaceID, into existingID: BrowserExtensionTabGroupID?
    ) throws -> BrowserExtensionTabGroup
    @discardableResult
    func update(
        _ id: BrowserExtensionTabGroupID, in spaceID: SpaceID,
        title: String?, color: BrowserExtensionTabGroupColor?, isCollapsed: Bool?
    ) throws -> BrowserExtensionTabGroup
    func ungroup(_ tabs: [TabID], in spaceID: SpaceID)
    func move(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID, to index: Int) throws -> BrowserExtensionTabGroup

    /// Drops closed tabs and Spaces, emitting `.removed` for every group the
    /// repair empties. Called from the extension coordinator's own reconcile,
    /// so a group cannot outlive the tabs that gave it a reason to exist.
    func repair(using session: BrowserSession)
    func events(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent>
    func membershipEvents(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent.Membership>
}

extension BrowserExtensionTabGroupHandling {
    func move(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID, to index: Int) throws -> BrowserExtensionTabGroup {
        throw BrowserExtensionTabGroupBrokerError.failedToMove
    }
}
