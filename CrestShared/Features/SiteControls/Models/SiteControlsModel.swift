import SwiftUI

/// Site Controls for one page while they are open: what they show, read from
/// the core's read model, the command catalog and the page, and where they
/// are, the root or a page opened over it. A platform shows the same model in
/// its own shell, a popover or a sheet; what differs by platform comes from
/// ``SiteControlsPlatform`` as data.
@Observable
@MainActor
final class SiteControlsModel {
    // MARK: - Types

    /// One action as a tile, a row or the editor shows it now.
    struct ActionItem: Identifiable {
        let action: SiteControlAction
        let state: SiteControlActionState
        /// The keys the action's command runs by here.
        let shortcut: BrowserShortcut?

        var id: String { action.name }
        var isOn: Bool { state.isOn }

        var title: LocalizedStringResource {
            state.title ?? (state.isOn ? action.onTitle : nil) ?? action.title
        }

        var shortTitle: LocalizedStringResource {
            state.shortTitle ?? (state.isOn ? action.onShortTitle : nil) ?? action.shortTitle
        }

        var symbol: String { (state.isOn ? action.onSymbol : nil) ?? action.symbol }

        /// The help a tile shows: the action's title, and its keys.
        var help: String {
            let title = String(localized: title)
            guard let shortcut else { return title }
            return "\(title) (\(shortcut.displayString))"
        }
    }

    /// An action the person drags within Site Controls, from the row on top
    /// or the editor's list, drawn as its tile under the pointer.
    struct ActionDrag {
        /// Which drag this is, so a gesture that ends late drops only its own.
        let id = UUID()
        let action: SiteControlAction
        /// Whether it was picked up from the row on top, which letting it go
        /// away from the row takes it off.
        let isFromRow: Bool
        /// The tile's size as it follows the pointer.
        let size: CGSize
        /// Where the pointer holds the tile, from the tile's center.
        let grab: CGSize
        /// Where the pointer is, in ``SiteControlsModel/space``.
        var location: CGPoint

        /// The tile's center as it follows the pointer.
        var center: CGPoint { CGPoint(x: location.x - grab.width, y: location.y - grab.height) }
    }

    // MARK: - Static Variables

    /// The space a drag's pointer and the row on top are measured in: all of
    /// Site Controls.
    static let space = NamedCoordinateSpace.named("crest.site-controls")

    /// How long after a drag the tile or row let go over does not take the
    /// release as a click.
    private static let activationSuppression: Duration = .milliseconds(250)

    // MARK: - Variables

    let platform: any SiteControlsPlatform

    /// The pages open over the root, the root first left out.
    private(set) var path: [SiteControlsPage] = []
    /// The root's height as last laid out, which every page keeps so a
    /// popover never resizes as the person moves between them.
    var rootHeight: CGFloat?
    /// Whether the actions page edits the row on top rather than running the rest.
    var isEditingActions = false
    /// The slot of the row on top the editor puts the next chosen action in.
    var selectedSlot = 0
    /// Whether a waiting permission request is answered for the page's Space
    /// from now on, rather than this once.
    var remembersPermission = true
    /// The action being dragged, from the row on top or the editor's list.
    private(set) var drag: ActionDrag?
    /// The row on top's frame in ``space``, which a drag lands in.
    var actionRowFrame: CGRect = .zero
    /// Whether a drag just ended, so the click it ends with runs nothing.
    private(set) var suppressesActivation = false
    @ObservationIgnored private var activationSuppressionTask: Task<Void, Never>?

    var page: BrowserPlatformPage { platform.page }
    var core: CrestCore { platform.core }

    // MARK: - Initializers

    init(platform: any SiteControlsPlatform, page: SiteControlsPage? = nil) {
        self.platform = platform
        if let page { path = [page] }
    }

    // MARK: - Actions - Navigation

    /// The page open on top, or nil while the root shows.
    var shownPage: SiteControlsPage? { path.last }

    /// Opens `page` over what shows.
    func open(_ page: SiteControlsPage) {
        guard path.last != page else { return }
        drag = nil
        path.append(page)
    }

    /// Opens the actions page editing the row on top, with the first slot chosen.
    func editActions(selecting slot: Int = 0) {
        isEditingActions = true
        selectedSlot = slot
        open(.actions)
    }

    /// Goes back to the root from any page, as a request that waits there does.
    func showRoot() {
        drag = nil
        path.removeAll()
        isEditingActions = false
    }

    /// Goes back to what showed before the page on top.
    func back() {
        guard !path.isEmpty else { return }
        drag = nil
        if path.removeLast() == .actions { isEditingActions = false }
    }

    // MARK: - Actions - Identity

    /// The page's title, or its host while it has none.
    var title: String {
        let title = page.live.title
        if !title.isEmpty { return title }
        return host ?? String(localized: "Site Controls")
    }

    /// The host of the site the page shows.
    var host: String? {
        page.live.displayURL?.host().flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The site's origin, as Connection names it, and the one its permissions
    /// and blocking are decided for.
    var origin: SiteOrigin? {
        page.live.displayURL.flatMap(SiteOrigin.init(url:))
    }

    /// The page's connection as the core holds it.
    var security: PageSecurity { page.live.security }

    /// An HTTPS page the engine judged secure but whose verified trust it
    /// could not hand over, on a platform that shows certificates. Without one
    /// to show, the page is not called secure.
    var isUnconfirmedSecure: Bool {
        platform.offersCertificates && security.isSecure && page.live.displayURL?.webScheme?.isSecure == true
            && platform.certificateReview == nil
    }

    var connectionTitle: LocalizedStringResource {
        isUnconfirmedSecure ? "Connection Details Unavailable" : security.title
    }

    var connectionSymbol: String { isUnconfirmedSecure ? "lock" : security.symbol }

    var connectionTint: Color {
        if isUnconfirmedSecure { return .secondary }
        if security.isSecure { return CrestColor.success }
        return security.isHazardous ? CrestColor.danger : CrestColor.warning
    }

    // MARK: - Actions - Actions

    /// The actions on top, as they stand for the page now.
    var topActions: [ActionItem] {
        core.state.siteControlTopActions.actions.map(item)
    }

    /// Every action the device offers for the page now, in catalog order.
    var offeredActions: [SiteControlAction] {
        SiteControlAction.all.filter { $0.isOffered(in: core.state) && platform.state(of: $0).isOffered }
    }

    /// The offered actions not on top, which More Actions counts.
    var moreActions: [SiteControlAction] {
        let top = Set(core.state.siteControlTopActions.actions)
        return offeredActions.filter { !top.contains($0) }
    }

    /// `action` as it stands for the page now. One whose state follows the
    /// page's tab, such as Pin Tab, is on while the tab is in that place.
    func item(_ action: SiteControlAction) -> ActionItem {
        var state = platform.state(of: action)
        if let placement = action.onWhileTabIs { state.isOn = platform.tab?.placement == placement }
        return ActionItem(action: action, state: state, shortcut: action.command.flatMap { platform.shortcut(for: $0) })
    }

    /// Runs `action`, putting Site Controls away first unless the action
    /// shows its result in them or in a notice.
    func run(_ action: SiteControlAction) {
        guard platform.state(of: action).isAvailable else { return }
        if !action.keepsSiteControlsOpen { platform.dismiss() }
        platform.run(action)
    }

    /// Puts `action` in `slot` of the row on top; one already there trades places.
    func place(_ action: SiteControlAction, in slot: Int) {
        _ = try? core.send(PlaceSiteControlTopAction(action: action, slot: slot))
    }

    /// Puts `action` in the slot the editor chose, and moves the choice on to
    /// the next slot, or back to the first after the last one there can be.
    func placeInSelectedSlot(_ action: SiteControlAction) {
        place(action, in: selectedSlot)
        let next = selectedSlot + 1
        let slots = min(core.state.siteControlTopActions.actions.count + 1, SiteControlTopActions.maximumCount)
        selectedSlot = next < slots ? next : 0
    }

    /// Moves `action` to `index` of the actions on top, or brings it in there.
    func move(_ action: SiteControlAction, to index: Int) {
        _ = try? core.send(MoveSiteControlTopAction(action: action, index: index))
    }

    /// Takes `action` off the top, unless it is the last one there.
    func remove(_ action: SiteControlAction) {
        _ = try? core.send(RemoveSiteControlTopAction(action: action))
        selectedSlot = min(selectedSlot, max(core.state.siteControlTopActions.actions.count - 1, 0))
    }

    func resetActions() {
        _ = try? core.send(ResetSiteControlTopActions())
        selectedSlot = 0
    }

    // MARK: - Actions - Dragging

    /// Picks `drag`'s action up, unless one is already being dragged.
    func pickUp(_ drag: ActionDrag) {
        guard self.drag == nil else { return }
        self.drag = drag
    }

    /// Carries the dragged action on to `location`, in ``space``.
    func carry(to location: CGPoint) {
        drag?.location = location
    }

    /// Lets the dragged action go: over the row it lands where the gap is;
    /// away from the row, one picked up from there leaves it unless it is the
    /// last one; anywhere else nothing changes.
    func endDrag() {
        guard let drag else { return }
        if let index = dropIndex {
            move(drag.action, to: index)
        } else if dragRemoves {
            remove(drag.action)
        }
        self.drag = nil
        suppressActivation()
    }

    /// Drops the dragged action where it came from, as a drag the system
    /// takes away does: the drag `id` names, or whichever is under way.
    func cancelDrag(_ id: UUID? = nil) {
        guard let drag, id == nil || drag.id == id else { return }
        self.drag = nil
        suppressActivation()
    }

    /// Where in the row on top the dragged action would land, while it is
    /// held over the row; nil elsewhere.
    var dropIndex: Int? {
        guard let drag, actionRowFrame.width > 0 else { return nil }
        let reach = actionRowFrame.insetBy(dx: -CrestSpacing.medium, dy: -drag.size.height / 2)
        guard reach.contains(drag.center) else { return nil }
        let slots = dropSlots
        // The editor's row always lays out every slot there can be, empty
        // ones too, so a drag over it lands in the slot it is over.
        let shown = isEditingActions && shownPage != nil ? SiteControlTopActions.maximumCount : slots
        let index = Int((drag.center.x - actionRowFrame.minX) / (actionRowFrame.width / CGFloat(shown)))
        return min(max(index, 0), slots - 1)
    }

    /// Whether letting the dragged action go now takes it off the row: it
    /// came from there, it is held away from the row, and others stay.
    var dragRemoves: Bool {
        guard let drag, drag.isFromRow, dropIndex == nil else { return false }
        return core.state.siteControlTopActions.actions.count > 1
    }

    /// How many places a drag over the row chooses between: the actions it
    /// does not carry, and one more while there is room.
    private var dropSlots: Int {
        let actions = core.state.siteControlTopActions.actions
        guard let drag else { return actions.count }
        let others = actions.contains(drag.action) ? actions.count - 1 : actions.count
        return min(others + 1, SiteControlTopActions.maximumCount)
    }

    /// Keeps the click a drag ends with from running the tile or row it ends
    /// over, for a moment.
    private func suppressActivation() {
        suppressesActivation = true
        activationSuppressionTask?.cancel()
        activationSuppressionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.activationSuppression)
            guard !Task.isCancelled else { return }
            self?.suppressesActivation = false
        }
    }

    // MARK: - Actions - Waiting

    /// Answers the waiting request: for the page's Space, or this once.
    func answer(_ request: BrowserPagePermissionController.Request, allows: Bool) {
        let response: BrowserSitePermissionPromptResponse =
            switch (allows, remembersPermission) {
            case (true, true): .grantPersistently
            case (true, false): .allowOnce
            case (false, true): .denyPersistently
            case (false, false): .denyOnce
            }
        page.sitePermissionRequests.resolve(request.id, response: response)
        remembersPermission = true
    }

    // MARK: - Actions - Blocking

    /// What the page's Space offers for blocking on its site, or nil where it
    /// blocks nothing.
    var contentBlocking: SiteContentBlockingSwitch? {
        SiteContentBlockingSwitch(core: core, spaceID: page.spaceID, url: page.live.documentURL)
    }

    /// Whether the page's engine blocks ads and trackers at all.
    var offersContentBlocking: Bool {
        ShortcutCommand.toggleContentBlocking.isOffered(in: core.state)
    }

    var blockedElements: BrowserBlockedElements {
        BrowserBlockedElements(core: core, pageURL: page.live.documentURL)
    }

    /// What the filter lists that are on keep off a page, in the order Site
    /// Controls name them.
    var blockedKinds: [ContentBlockKind] {
        let blocked = Set(core.state.filterLists.lists.filter(\.isOn).flatMap(\.list.blocks))
        return ContentBlockKind.all.filter(blocked.contains)
    }

    /// The level every site blocks at, or Custom where the person changed
    /// which lists it turns on.
    var blockingLevelTitle: LocalizedStringResource {
        let lists = core.state.filterLists
        return lists.isCustomized ? "Custom" : lists.level.title
    }

    // MARK: - Actions - Permissions

    /// The capabilities this device's pages can use, each with its decision
    /// for the site in the page's Space.
    var permissions: [(permission: SitePermission, decision: SitePermissionDecision)] {
        guard let origin else { return [] }
        return SitePermission.all.filter { $0.platforms.contains(.current) }.map {
            ($0, page.permissionCenter.decision(for: $0, origin: origin, in: page.spaceID))
        }
    }

    /// Whether the site asked for `permission`: a decision for it stands, it
    /// waits on the person now, or the page tried a pop-up it blocked.
    func wasAsked(for permission: SitePermission, decision: SitePermissionDecision) -> Bool {
        decision.verdict != .ask || page.sitePermissionRequests.current?.permission == permission
            || (permission == .popups && page.blockedPopupNotice != nil)
    }

    func setDecision(_ decision: SitePermissionDecision, for permission: SitePermission) {
        guard let origin else { return }
        page.permissionCenter.setDecision(decision, for: permission, origin: origin, in: page.spaceID)
    }

    /// What the Permissions row says where it has no room for a capability's
    /// name: how many are allowed or blocked, or Ask.
    var compactPermissionSummary: String {
        let decided = permissions.filter { $0.decision.verdict != .ask }
        let allowed = decided.filter { $0.decision.grants }.count
        if allowed > 0 { return String(localized: "\(allowed) allowed") }
        return decided.isEmpty ? String(localized: "Ask") : String(localized: "\(decided.count) blocked")
    }

    /// What the Permissions row says: the one capability allowed or blocked,
    /// how many are, or Ask.
    var permissionSummary: String {
        let decided = permissions.filter { $0.decision.verdict != .ask }
        let allowed = decided.filter { $0.decision.grants }
        if let only = allowed.first, allowed.count == 1 {
            return String(localized: "\(String(localized: only.permission.title)) allowed")
        }
        if allowed.count > 1 { return String(localized: "\(allowed.count) allowed") }
        if let only = decided.first, decided.count == 1 {
            return String(localized: "\(String(localized: only.permission.title)) blocked")
        }
        if decided.count > 1 { return String(localized: "\(decided.count) blocked") }
        return String(localized: "Ask")
    }

    // MARK: - Actions - Downloads

    /// The downloads of the page's Space, newest first.
    var downloads: [DownloadState] {
        core.state.downloads.filter { $0.profileID == page.profileID }
    }

    /// What the Downloads row says: how many are under way, or nothing.
    var downloadsSummary: String? {
        let live = downloads.filter(\.phase.isTransferring).count
        return live > 0 ? String(localized: "\(live) in progress") : nil
    }

    // MARK: - Actions - Zoom

    var zoomLabel: String { page.pageZoom.pageZoomPercentage }

    var canZoom: Bool { platform.canRun(.zoomIn) || platform.canRun(.zoomOut) }
}
