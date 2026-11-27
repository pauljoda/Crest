import Foundation
import SwiftUI

/// Shared window-level browser coordination owned by both macOS
/// (`BrowserRootModel`) and iOS/iPadOS (`MobileBrowserRootModel`). Platform
/// root models supply only their shell-specific navigation, focus, and sidebar
/// morphing behavior.
@MainActor
protocol BrowserWindowRootModel: AnyObject {
    associatedtype Pages: BrowserPageOwner

    var browser: BrowserStore { get }
    var pages: Pages { get }
    var spaceAccess: BrowserSpaceAccessController { get }
    var layoutPersistence: BrowserWindowLayoutPersistence { get }
    var isBrowserPrepared: Bool { get }
    var address: String { get set }
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction { get set }
    var splitWidthTransaction: BrowserSplitWidthTransaction { get set }
}

// MARK: - Actions - Reconciliation

extension BrowserWindowRootModel {
    func reconcileTabIcons() {
        pages.reconcileTabIcons()
    }

    /// Applies current Space credential preferences to resident pages.
    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess()
    }

    func reconcileContentBlocking() {
        guard isBrowserPrepared else { return }
        Task { await pages.reconcileContentBlocking() }
    }

    func reloadContentBlocking() {
        guard isBrowserPrepared else { return }
        Task { await pages.reloadContentBlocking() }
    }

    func relockProtectedSpaces(_ spaceIDs: Set<UUID>) {
        // The Space itself, not just its ID: relocking has to reach the
        // profile its archived tab state is filed under, and that state
        // outlives the resident pages an ID alone can find.
        for space in browser.spaceModels where spaceIDs.contains(space.id) {
            pages.relockProtectedSpace(space)
        }
    }
}

// MARK: - Actions - Selection & Access

extension BrowserWindowRootModel {
    var selectedSpaceIsLocked: Bool {
        guard let space = browser.shownSpace else { return false }
        return spaceAccess.isLocked(space)
    }

    var lockedSpaceIDs: Set<UUID> {
        Set(browser.spaceModels.filter(spaceAccess.isLocked).map(\.id))
    }

    var selectedTabAssignment: BrowserTabRuntimeAssignment? {
        browser.shownTabAssignment
    }

    func isPaletteSourceAvailable(_ source: BrowserTabRuntimeAssignment) -> Bool {
        browser.isPaletteSourceAvailable(source, accessController: spaceAccess)
    }
}

// MARK: - Actions - Sidebar Width

extension BrowserWindowRootModel {
    var sidebarWidth: CGFloat {
        sidebarWidthTransaction.width
    }

    var sidebarWidthBinding: Binding<CGFloat> {
        Binding(
            get: { self.sidebarWidthTransaction.width },
            set: { self.sidebarWidthTransaction.resize(to: $0) }
        )
    }

    func restoreSidebarWidth(_ width: CGFloat) {
        layoutPersistence.restoreSidebarWidth(width, transaction: &sidebarWidthTransaction)
    }

    func commitSidebarWidth(_ width: CGFloat) -> CGFloat? {
        layoutPersistence.commitSidebarWidth(width, transaction: &sidebarWidthTransaction)
    }
}

// MARK: - Actions - Split Layout

extension BrowserWindowRootModel {
    /// The cards the content area presents, as the window's read model
    /// publishes them, so SwiftUI observes what changes when membership does.
    var presentedSplitMembers: [TabStateModel] {
        browser.shownCards
    }

    /// The group the presented cards belong to, or `nil` when one tab presents
    /// alone. Column fractions are stored per group, so a lone tab has no
    /// layout to store.
    var presentedSplitGroupID: UUID? {
        browser.shownSpace.flatMap(browser.shownSplitGroupID(in:))
    }

    var splitWidthTransactionBinding: Binding<BrowserSplitWidthTransaction> {
        Binding(
            get: { self.splitWidthTransaction },
            set: { self.splitWidthTransaction = $0 }
        )
    }

    func seedSplitColumnFractions() {
        layoutPersistence.seedSplitLayout(
            groupID: presentedSplitGroupID, memberCount: presentedSplitMembers.count,
            transaction: &splitWidthTransaction
        )
    }

    func commitSplitColumnFractions(_ fractions: [Double]) {
        layoutPersistence.commitSplitLayout(fractions, groupID: presentedSplitGroupID)
    }
}

// MARK: - Actions - Downloads

extension BrowserWindowRootModel {
    var selectedUtilityDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    var newUtilityDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }
}
