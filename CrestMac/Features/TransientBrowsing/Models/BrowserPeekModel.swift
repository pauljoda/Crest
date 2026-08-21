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
        BrowserTransientSessionPolicy.availableSpaces(
            in: browser.session.spaces,
            deletingSpaceIDs: browser.deletingSpaceIDs,
            requestSpaceID: request.spaceID,
            isLocked: spaceAccess.isLocked
        )
    }

    @discardableResult
    func preparePage(isActive: Bool) -> Bool {
        let space: BrowserSpace
        switch sourceDisposition {
        case .notPresented:
            releaseLease()
            return false
        case .sourceMissing:
            dismissUnavailableRequest()
            return false
        case .sourceLocked:
            setSourceLocked(true)
            return false
        case .usable(let usableSpace):
            space = usableSpace
        }
        if let pageLease,
            BrowserTransientSessionPolicy.reusesLease(
                leaseAssignment: pageLease.assignment,
                requestAssignment: request.assignment,
                leaseCanBeReused: pageLease.canBeReused
            )
        {
            pageLease.setActive(isActive)
            return true
        }
        pageLease?.release()
        guard let pages else { return true }
        pageLease = pages.makeTransientPageLease(
            url: request.url,
            in: space,
            onDownloadOnlyNavigation: { [weak coordinator, request = self.request] in
                coordinator?.dismissPeek(request)
            }
        )
        guard let pageLease else {
            dismissUnavailableRequest()
            return false
        }
        pageLease.setActive(isActive)
        return true
    }

    func restorePage() {
        guard isCurrentRequest else {
            releaseLease()
            return
        }
        guard let pageLease else { return }
        switch disposition(ofSpaceMatching: pageLease.assignment) {
        case .notPresented:
            releaseLease()
        case .sourceMissing:
            dismissUnavailableRequest()
        case .sourceLocked:
            setSourceLocked(true)
        case .usable:
            pageLease.restore()
        }
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
            let promotion = BrowserTransientSessionPolicy.promotionSpaces(
                source: browser.space(matching: request.assignment),
                destination: browser.space(matching: destinationAssignment),
                isLocked: spaceAccess.isLocked
            ),
            let url = page.url ?? Optional(request.url),
            let tabID = browser.openNewTab(
                url: url,
                matching: BrowserSpaceRuntimeAssignment(
                    space: promotion.destination
                )
            ),
            let currentDestination = browser.space(
                matching: BrowserSpaceRuntimeAssignment(
                    space: promotion.destination
                )
            )
        else { return false }

        let adoptedLivePage =
            BrowserTransientSessionPolicy.adoptsLivePage(
                leaseAssignment: pageLease.assignment,
                destination: currentDestination
            )
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
        releaseLease()
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
        switch sourceDisposition {
        case .notPresented, .sourceMissing, .sourceLocked:
            // A window that is no longer showing this Peek, or is showing it
            // over a Space that has gone or locked, keeps no page alive. Only
            // the lease goes: the overlay itself is the window's business.
            releaseLease()
        case .usable:
            pageLease?.setActive(isActive)
        }
    }

    func setSourceLocked(_ isLocked: Bool) {
        guard isLocked else { return }
        releaseLease()
    }

    func setSourceAvailable(_ isAvailable: Bool) {
        guard !isAvailable else { return }
        dismissUnavailableRequest()
    }

    func releaseForDisappearance() {
        guard !wasPromoted else { return }
        releaseLease()
    }

    private var isCurrentRequest: Bool {
        coordinator.isPresentingPeek(request)
    }

    private var sourceDisposition: BrowserTransientLeaseDisposition {
        disposition(ofSpaceMatching: request.assignment)
    }

    private func disposition(
        ofSpaceMatching assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserTransientLeaseDisposition {
        BrowserTransientSessionPolicy.disposition(
            isPresentingRequest: isCurrentRequest,
            space: browser.space(matching: assignment),
            isLocked: spaceAccess.isLocked
        )
    }

    private func releaseLease() {
        pageLease?.release()
        pageLease = nil
    }
}
