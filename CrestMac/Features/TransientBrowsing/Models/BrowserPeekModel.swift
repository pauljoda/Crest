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

    var motionState: BrowserPeekMotionState? {
        coordinator.motionState(for: request)
    }

    var isPullStaged: Bool {
        motionState != nil && coordinator.presentationPhase(for: request) == .staged
    }

    func finishReturningPull() {
        guard motionState?.returnsToSource == true else { return }
        releaseLease()
        coordinator.cancelStagedPeek(id: request.id)
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
            pageLease.setActive(isActive && isSelected)
            return true
        }
        pageLease?.release()
        guard let pages else { return true }
        pageLease = pages.makePeekPageLease(
            request: request,
            in: space,
            onDownloadOnlyNavigation: { [weak coordinator, request = self.request] in
                coordinator?.dismissPeek(request)
            }
        )
        guard let pageLease else {
            dismissUnavailableRequest()
            return false
        }
        pageLease.setActive(isActive && isSelected)
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

    @discardableResult
    func promote(to destinationAssignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard let pages,
            isCurrentRequest,
            !wasPromoted,
            let pageLease,
            let page = pageLease.page,
            let outcome = BrowserTransientPagePromotion(
                requestID: request.id,
                url: page.url ?? request.url,
                sourceAssignment: request.assignment,
                leaseAssignment: pageLease.assignment,
                destinationAssignment: destinationAssignment
            ).perform(
                in: browser,
                isLocked: spaceAccess.isLocked,
                adoptPage: { tabID, destination in
                    pages.adoptTransientPage(pageLease, as: tabID, in: destination)
                }
            )
        else { return false }

        wasPromoted = true
        if outcome == .openedNewPage {
            pageLease.release()
        }
        pages.select(session: browser.presented)
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
            // Release inaccessible content without changing the window's presentation.
            releaseLease()
        case .usable:
            pageLease?.setActive(isActive && isSelected)
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
        if isCurrentRequest {
            pageLease?.setActive(false)
        } else {
            releaseLease()
        }
    }

    var isSelected: Bool { request.isSelected(in: browser.presented) }

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
            space: request.hasSource(in: browser.session) ? browser.space(matching: assignment) : nil,
            isLocked: spaceAccess.isLocked
        )
    }

    private func releaseLease() {
        pageLease?.release()
        pageLease = nil
    }
}
