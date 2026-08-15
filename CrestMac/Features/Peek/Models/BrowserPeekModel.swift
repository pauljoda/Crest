import Observation

@Observable
@MainActor
final class BrowserPeekModel {
    let request: BrowserPeekRequest
    private(set) var pageLease: BrowserTransientPageLease?
    private(set) var wasPromoted = false

    @ObservationIgnored let browser: BrowserStore
    @ObservationIgnored let pages: BrowserPagePool?
    @ObservationIgnored private let spaceAccess: BrowserSpaceAccessController
    @ObservationIgnored private let coordinator: BrowserTransientBrowsingCoordinator

    init(
        request: BrowserPeekRequest,
        browser: BrowserStore,
        pages: BrowserPagePool,
        spaceAccess: BrowserSpaceAccessController,
        coordinator: BrowserTransientBrowsingCoordinator
    ) {
        self.request = request
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.coordinator = coordinator
    }

    init(
        previewing request: BrowserPeekRequest,
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        coordinator: BrowserTransientBrowsingCoordinator
    ) {
        self.request = request
        self.browser = browser
        pages = nil
        self.spaceAccess = spaceAccess
        self.coordinator = coordinator
    }

    var space: BrowserSpace? {
        browser.space(matching: request.assignment)
    }

    var page: BrowserPage? {
        pageLease?.page
    }

    var availableSpaces: [BrowserSpace] {
        browser.session.spaces.filter {
            !browser.deletingSpaceIDs.contains($0.id)
                && ($0.id == request.spaceID || !spaceAccess.isLocked($0))
        }
    }

    @discardableResult
    func preparePage(isActive: Bool) -> Bool {
        guard isCurrentRequest else {
            pageLease?.release()
            pageLease = nil
            return false
        }
        guard let space else {
            dismissUnavailableRequest()
            return false
        }
        guard !spaceAccess.isLocked(space) else {
            setSourceLocked(true)
            return false
        }
        if let pageLease,
            pageLease.assignment == request.assignment,
            pageLease.canBeReused
        {
            pageLease.setActive(isActive)
            return true
        }
        pageLease?.release()
        guard let pages else { return true }
        pageLease = pages.makeTransientPageLease(url: request.url, in: space)
        guard let pageLease else {
            dismissUnavailableRequest()
            return false
        }
        pageLease.setActive(isActive)
        return true
    }

    func restorePage() {
        guard isCurrentRequest else {
            pageLease?.release()
            pageLease = nil
            return
        }
        guard let pageLease else { return }
        guard let space = browser.space(matching: pageLease.assignment) else {
            dismissUnavailableRequest()
            return
        }
        guard !spaceAccess.isLocked(space) else {
            setSourceLocked(true)
            return
        }
        pageLease.restore()
    }

    func recordCompletedNavigation() {
        guard isCurrentRequest,
            let pageLease,
            let page = pageLease.page,
            let url = page.url
        else { return }
        browser.recordVisit(
            url: url,
            title: page.title,
            matching: pageLease.assignment
        )
    }

    @discardableResult
    func promote(to destinationAssignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard let pages,
            isCurrentRequest,
            let pageLease,
            let page = pageLease.page,
            pageLease.assignment == request.assignment,
            let sourceSpace = browser.space(matching: request.assignment),
            !spaceAccess.isLocked(sourceSpace),
            let destinationSpace = browser.space(
                matching: destinationAssignment
            ),
            !spaceAccess.isLocked(destinationSpace),
            let url = page.url ?? Optional(request.url),
            let tabID = browser.openNewTab(
                url: url,
                matching: BrowserSpaceRuntimeAssignment(
                    space: destinationSpace
                )
            ),
            let currentDestination = browser.space(
                matching: BrowserSpaceRuntimeAssignment(
                    space: destinationSpace
                )
            )
        else { return false }

        let adoptedLivePage =
            pageLease.assignment
            == BrowserSpaceRuntimeAssignment(space: currentDestination)
            && pages.adoptTransientPage(
                pageLease,
                as: tabID,
                in: currentDestination
            )
        wasPromoted = true
        if !adoptedLivePage {
            pageLease.release()
        }
        pages.select(session: browser.session)
        coordinator.dismissPeek(request)
        return true
    }

    func dismiss() {
        coordinator.dismissPeek(request)
    }

    func dismissUnavailableRequest() {
        pageLease?.release()
        pageLease = nil
        coordinator.dismissPeek(request)
    }

    func selectLockedSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard let candidate = browser.space(matching: assignment),
            !spaceAccess.isLocked(candidate),
            coordinator.dismissPeek(request)
        else { return }
        browser.selectSpace(assignment.spaceID)
    }

    func setActive(_ isActive: Bool) {
        guard isCurrentRequest,
            let space = browser.space(matching: request.assignment),
            !spaceAccess.isLocked(space)
        else {
            pageLease?.release()
            pageLease = nil
            return
        }
        pageLease?.setActive(isActive)
    }

    func setSourceLocked(_ isLocked: Bool) {
        guard isLocked else { return }
        pageLease?.release()
        pageLease = nil
    }

    func setSourceAvailable(_ isAvailable: Bool) {
        guard !isAvailable else { return }
        dismissUnavailableRequest()
    }

    func releaseForDisappearance() {
        guard !wasPromoted else { return }
        pageLease?.release()
        pageLease = nil
    }

    private var isCurrentRequest: Bool {
        coordinator.isPresentingPeek(request)
    }
}
