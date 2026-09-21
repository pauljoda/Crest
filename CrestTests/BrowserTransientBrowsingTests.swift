import XCTest

@testable import Crest

@MainActor
final class BrowserTransientBrowsingTests: XCTestCase {
    func testLinkPullCancelsWhenTheSourceRuntimeAssignmentChanges() throws {
        let tab = BrowserTab(
            title: "Source", url: try XCTUnwrap(URL(string: "https://example.com/source")), placement: .current)
        let spaceID = SpaceID()
        var source: BrowserPageNavigationContext? = BrowserPageNavigationContext(
            tab: tab, spaceID: spaceID, profileID: UUID())
        let coordinator = BrowserTransientBrowsingCoordinator()
        let handler = BrowserLinkPullHandler(context: { source }, handle: coordinator.handleLinkDrag)
        let sample = BrowserLinkPullSample(
            location: CGPoint(x: 0.4, y: 0.4), size: CGSize(width: 800, height: 600), time: 1)
        XCTAssertTrue(
            handler.begin(
                url: try XCTUnwrap(URL(string: "https://example.com/destination")), label: nil,
                origin: CGPoint(x: 0.2, y: 0.2), sample: sample))
        XCTAssertEqual(coordinator.peekPresentationPhase, .staged)

        source = BrowserPageNavigationContext(tab: tab, spaceID: spaceID, profileID: UUID())

        XCTAssertFalse(handler.validateSource())
        XCTAssertFalse(handler.isActive)
        XCTAssertNil(coordinator.peekRequest)
        handler.end(sample)
        XCTAssertNil(coordinator.peekRequest)
    }

    func testLinkPullReleaseCommitsOnlyInsideItsSourceWindow() throws {
        let source = BrowserPageNavigationContext(
            tab: BrowserTab(
                title: "Source", url: try XCTUnwrap(URL(string: "https://example.com/source")), placement: .current),
            spaceID: SpaceID(), profileID: UUID())
        let coordinator = BrowserTransientBrowsingCoordinator()
        let handler = BrowserLinkPullHandler(context: { source }, handle: coordinator.handleLinkDrag)
        let url = try XCTUnwrap(URL(string: "https://example.com/destination"))
        let origin = CGPoint(x: 0.2, y: 0.2)
        let sample = BrowserLinkPullSample(
            location: CGPoint(x: 0.4, y: 0.4), size: CGSize(width: 800, height: 600), time: 1)
        XCTAssertTrue(handler.begin(url: url, label: nil, origin: origin, sample: sample))
        let request = try XCTUnwrap(coordinator.peekRequest)

        handler.end(BrowserLinkPullSample(location: sample.location, size: sample.size, time: 2))

        XCTAssertEqual(coordinator.peekRequest, request)
        XCTAssertEqual(coordinator.peekPresentationPhase, .committed)
        XCTAssertFalse(handler.isActive)
        handler.cancel()
        XCTAssertEqual(coordinator.peekRequest, request)

        XCTAssertTrue(handler.begin(url: url, label: nil, origin: origin, sample: sample))
        handler.end(
            BrowserLinkPullSample(
                location: CGPoint(x: 1.1, y: 0.4), size: sample.size, time: 2))

        XCTAssertNil(coordinator.peekRequest)
        XCTAssertFalse(handler.isActive)
    }

    func testPullReleaseRequiresDistanceAndRejectsVelocityBackTowardTheLink() {
        for translation in [CGSize(width: 80, height: 0), CGSize(width: -60, height: 80)] {
            XCTAssertTrue(BrowserLinkDragReleasePolicy.opensPeek(translation: translation, velocity: translation))
            XCTAssertFalse(
                BrowserLinkDragReleasePolicy.opensPeek(
                    translation: translation,
                    velocity: CGSize(width: -translation.width, height: -translation.height)))
            XCTAssertTrue(BrowserLinkDragReleasePolicy.opensPeek(translation: translation, velocity: .zero))
        }
        XCTAssertFalse(
            BrowserLinkDragReleasePolicy.opensPeek(
                translation: CGSize(width: 4, height: 3), velocity: CGSize(width: 900, height: 900)))
    }

    func testReturningPullStaysStagedAndLateUpdatesCannotReplaceAnotherPeek() throws {
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/pull")),
            sourceTabID: TabID(), sourceTitle: "Source",
            spaceAssignment: BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID()),
            trigger: .linkDrag)
        let coordinator = BrowserTransientBrowsingCoordinator()
        var state = BrowserPeekMotionState(
            origin: CGPoint(x: 0.2, y: 0.2),
            location: CGPoint(x: 0.4, y: 0.4), scale: 0.4)
        coordinator.beginPeekDrag(request, state: state)
        state.releasedAt = Date()
        state.returnsToSource = true
        coordinator.updatePeekDrag(id: request.id, state: state)
        XCTAssertEqual(coordinator.peekPresentationPhase, .staged)
        XCTAssertEqual(coordinator.peekRequest?.id, request.id)
        coordinator.cancelStagedPeek(id: request.id)
        XCTAssertNil(coordinator.peekMotionState)

        coordinator.beginPeekDrag(request, state: state)
        coordinator.presentPeek(request)
        let clickMotion = coordinator.peekMotionState
        coordinator.updatePeekDrag(id: request.id, state: state)
        XCTAssertNotNil(clickMotion?.releasedAt)
        XCTAssertEqual(coordinator.peekMotionState, clickMotion)
        XCTAssertEqual(coordinator.peekPresentationPhase, .committed)
        coordinator.cancelStagedPeek(id: request.id)
        XCTAssertEqual(coordinator.peekRequest?.id, request.id)
    }

    func testExternalURLsPreferAnExistingBrowserAndOtherwiseCreateOnlyAQuickWindow() {
        XCTAssertEqual(BrowserExternalLinkScenePolicy.existingBrowserPreference, ["*"])
        XCTAssertEqual(BrowserExternalLinkScenePolicy.primarySceneActivation, [])
        XCTAssertEqual(BrowserExternalLinkScenePolicy.quickWindowSceneActivation, ["*"])
    }

    func testEmptyQuickWindowRequestStartsWithoutNavigating() {
        let request = BrowserQuickWindowRequest.empty(
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            )
        )

        XCTAssertNil(request.initialURL)
    }

    func testQuickWindowCarriesTheSingletonMainBrowserForPromotion() throws {
        let request = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/reference")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            targetWindowID: .main
        )

        XCTAssertEqual(request.targetWindowID, .main)

        let restored = try JSONDecoder().decode(
            BrowserQuickWindowRequest.self,
            from: JSONEncoder().encode(request)
        )
        XCTAssertEqual(restored.targetWindowID, .main)
    }

    func testQuickWindowPresentationIdentityFocusesAnExactURLInTheSameSpace() throws {
        let spaceID = SpaceID()
        let profileID = UUID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let first = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: assignment
        )
        let duplicate = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: assignment
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(Set([first, duplicate]).count, 1)
        XCTAssertNotEqual(
            first,
            BrowserQuickWindowRequest(
                url: url,
                spaceAssignment: BrowserSpaceRuntimeAssignment(
                    spaceID: spaceID,
                    profileID: UUID()
                )
            )
        )
        XCTAssertNotEqual(
            BrowserQuickWindowRequest.empty(spaceAssignment: assignment),
            BrowserQuickWindowRequest.empty(spaceAssignment: assignment)
        )
        XCTAssertEqual(first.assignment.spaceID, spaceID)
        XCTAssertEqual(first.assignment.profileID, profileID)

        let restored = try JSONDecoder().decode(
            BrowserQuickWindowRequest.self,
            from: JSONEncoder().encode(first)
        )
        XCTAssertEqual(restored.assignment, assignment)
    }

    func testQuickWindowCarriesPresentationOriginWithoutChangingWindowIdentity() throws {
        let spaceID = SpaceID()
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let targetWindowID = BrowserWindowID()
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: 0.12,
            normalizedMinY: 0.28,
            normalizedWidth: 0.34,
            normalizedHeight: 0.05,
            normalizedTouchX: 0.21,
            normalizedTouchY: 0.31,
            label: "External link"
        )
        let request = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID()
            ),
            targetWindowID: targetWindowID,
            sourcePresentation: source
        )
        let sameWindowWithoutSource = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: request.assignment
        )

        XCTAssertEqual(request.sourcePresentation, source)
        XCTAssertEqual(request.targetWindowID, targetWindowID)
        XCTAssertEqual(request, sameWindowWithoutSource)
        XCTAssertEqual(Set([request, sameWindowWithoutSource]).count, 1)

        let restored = try JSONDecoder().decode(
            BrowserQuickWindowRequest.self,
            from: JSONEncoder().encode(request)
        )
        XCTAssertEqual(restored.sourcePresentation, source)
    }

    func testCoordinatorMatchesTheFullQuickWindowRequestBeyondPublicEquality() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let first = BrowserQuickWindowRequest(
            id: UUID(),
            url: url,
            spaceAssignment: assignment,
            targetWindowID: BrowserWindowID(),
            sourcePresentation: BrowserPeekSourcePresentation(
                normalizedMinX: 0.1,
                normalizedMinY: 0.2,
                normalizedWidth: 0.3,
                normalizedHeight: 0.04,
                label: "First"
            )
        )
        let equalityEquivalentReplacement = BrowserQuickWindowRequest(
            id: UUID(),
            url: url,
            spaceAssignment: assignment,
            targetWindowID: BrowserWindowID(),
            sourcePresentation: nil
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentQuickWindow(first)

        XCTAssertEqual(first, equalityEquivalentReplacement)
        XCTAssertFalse(
            coordinator.isPresentingQuickWindow(equalityEquivalentReplacement)
        )
        XCTAssertFalse(
            coordinator.dismissQuickWindow(equalityEquivalentReplacement)
        )
        XCTAssertTrue(coordinator.isPresentingQuickWindow(first))
        XCTAssertEqual(coordinator.quickWindowRequest?.id, first.id)
    }

    func testDelayedPeekCommitCannotReplaceANewerTransientPresentation() throws {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let first = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/first")),
            sourceTabID: TabID(),
            sourceTitle: "First",
            spaceAssignment: assignment,
            trigger: .longPress
        )
        let second = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/second")),
            sourceTabID: TabID(),
            sourceTitle: "Second",
            spaceAssignment: assignment,
            trigger: .longPress
        )
        let quickWindow = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/quick")),
            spaceAssignment: assignment
        )
        let coordinator = BrowserTransientBrowsingCoordinator()

        coordinator.stagePeek(first)
        coordinator.stagePeek(second)
        coordinator.commitPeek(first)

        XCTAssertEqual(coordinator.peekRequest, second)
        XCTAssertEqual(coordinator.peekPresentationPhase, .staged)

        coordinator.presentQuickWindow(quickWindow)
        coordinator.commitPeek(first)

        XCTAssertEqual(coordinator.quickWindowRequest, quickWindow)
        XCTAssertNil(coordinator.peekRequest)
        XCTAssertNil(coordinator.peekPresentationPhase)
    }

    func testRetargetingAQuickWindowRequestPreservesItsExactTargetWindowRuntime() throws {
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: 0.12,
            normalizedMinY: 0.28,
            normalizedWidth: 0.34,
            normalizedHeight: 0.05,
            normalizedTouchX: 0.21,
            normalizedTouchY: 0.31,
            label: "External link"
        )
        let targetWindowID = BrowserWindowID()
        let request = BrowserQuickWindowRequest(
            id: UUID(),
            url: try XCTUnwrap(URL(string: "https://example.com/original")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            targetWindowID: targetWindowID,
            sourcePresentation: source
        )
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )

        let revised = request.retargeted(
            to: try XCTUnwrap(URL(string: "https://example.com/revised")),
            assignment: replacementAssignment
        )

        XCTAssertEqual(revised.id, request.id)
        XCTAssertEqual(revised.assignment, replacementAssignment)
        XCTAssertEqual(revised.targetWindowID, targetWindowID)
        XCTAssertEqual(revised.sourcePresentation, source)
    }

    func testTransientActivityClockCoalescesPublicationWithoutLosingExactActivity() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = BrowserTransientActivityClock(
            now: start,
            publicationInterval: 15
        )

        clock.recordActivity(at: start.addingTimeInterval(5))
        XCTAssertEqual(clock.revision, 0)
        XCTAssertEqual(
            clock.inactivityRemaining(
                for: 60,
                at: start.addingTimeInterval(50)
            ),
            15
        )

        clock.recordActivity(at: start.addingTimeInterval(20))
        XCTAssertEqual(clock.revision, 1)
        clock.recordActivity(
            at: start.addingTimeInterval(21),
            restartsTimerImmediately: true
        )
        XCTAssertEqual(clock.revision, 2)
    }

    func testAutomaticPeekProtectsPinnedAndSavedRootsOnlyAcrossSites() throws {
        let spaceID = SpaceID()
        let profileID = UUID()
        let pinned = BrowserTab(
            title: "GitHub",
            url: try XCTUnwrap(URL(string: "https://github.com/crest/repository")),
            placement: .pinned
        )
        let context = BrowserPageNavigationContext(
            tab: pinned,
            spaceID: spaceID,
            profileID: profileID
        )

        XCTAssertNil(
            BrowserPeekPolicy.request(
                destinationURL: try XCTUnwrap(URL(string: "https://www.github.com/features")),
                context: context,
                isUserActivatedLink: true,
                isTopLevelNavigation: true,
                isAlternateModified: false
            )
        )

        let request = BrowserPeekPolicy.request(
            destinationURL: try XCTUnwrap(URL(string: "https://example.com/reference")),
            context: context,
            isUserActivatedLink: true,
            isTopLevelNavigation: true,
            isAlternateModified: false
        )

        XCTAssertEqual(request?.trigger, .protectedSavedSite)
        XCTAssertEqual(request?.sourceTabID, pinned.id)
        XCTAssertEqual(
            request?.assignment,
            BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: profileID
            )
        )
        XCTAssertEqual(request?.spaceID, spaceID)
    }

    func testOptionClickForcesPeekFromCurrentTabWhileNonLinkNavigationNeverDoes() throws {
        let current = BrowserTab(
            title: "Current",
            url: try XCTUnwrap(URL(string: "https://example.com")),
            placement: .current
        )
        let context = BrowserPageNavigationContext(
            tab: current,
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let destination = try XCTUnwrap(URL(string: "https://example.com/next"))

        XCTAssertEqual(
            BrowserPeekPolicy.request(
                destinationURL: destination,
                context: context,
                isUserActivatedLink: true,
                isTopLevelNavigation: true,
                isAlternateModified: true
            )?.trigger,
            .modifierClick
        )
        XCTAssertNil(
            BrowserPeekPolicy.request(
                destinationURL: destination,
                context: context,
                isUserActivatedLink: false,
                isTopLevelNavigation: true,
                isAlternateModified: true
            )
        )
    }

    func testNewTabModifiersBypassAutomaticPeekWhileOptionKeepsPriority() throws {
        let pinned = BrowserTab(
            title: "Pinned",
            url: try XCTUnwrap(URL(string: "https://example.com/root")),
            placement: .pinned
        )
        let context = BrowserPageNavigationContext(
            tab: pinned,
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let destination = try XCTUnwrap(URL(string: "https://another.test/reference"))

        XCTAssertNil(
            BrowserPeekPolicy.request(
                destinationURL: destination,
                context: context,
                isUserActivatedLink: true,
                isTopLevelNavigation: true,
                isAlternateModified: false,
                isNewTabModified: true
            )
        )
        XCTAssertEqual(
            BrowserPeekPolicy.request(
                destinationURL: destination,
                context: context,
                isUserActivatedLink: true,
                isTopLevelNavigation: true,
                isAlternateModified: true,
                isNewTabModified: true
            )?.trigger,
            .modifierClick
        )
    }

    func testPeekSourcePresentationBoundsHostileWebContentGeometryAndLabels() {
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: .nan,
            normalizedMinY: -.infinity,
            normalizedWidth: .infinity,
            normalizedHeight: 4,
            normalizedTouchX: 8,
            normalizedTouchY: -.infinity,
            label: String(repeating: "x", count: 1_000)
        )

        XCTAssertEqual(source.normalizedMinX, 0)
        XCTAssertEqual(source.normalizedMinY, 0)
        XCTAssertEqual(source.normalizedWidth, 0)
        XCTAssertEqual(source.normalizedHeight, 1)
        XCTAssertEqual(source.normalizedTouchX, 1)
        XCTAssertEqual(source.normalizedTouchY, 0)
        XCTAssertEqual(source.label.count, 160)
    }

    func testAutomaticPeekCanBeDisabledWithoutDisablingOptionClick() throws {
        let pinned = BrowserTab(
            title: "Pinned",
            url: try XCTUnwrap(URL(string: "https://example.com")),
            placement: .pinned
        )
        let context = BrowserPageNavigationContext(
            tab: pinned,
            spaceID: SpaceID(),
            profileID: UUID(),
            automaticallyOpensPeek: false
        )
        let destination = try XCTUnwrap(URL(string: "https://webkit.org"))

        XCTAssertNil(
            BrowserPeekPolicy.request(
                destinationURL: destination,
                context: context,
                isUserActivatedLink: true,
                isTopLevelNavigation: true,
                isAlternateModified: false
            )
        )
        XCTAssertNotNil(
            BrowserPeekPolicy.request(
                destinationURL: destination,
                context: context,
                isUserActivatedLink: true,
                isTopLevelNavigation: true,
                isAlternateModified: true
            )
        )
    }

    func testLegacySavedTabUsesItsCurrentURLAsPeekBoundary() throws {
        var saved = BrowserTab(
            title: "Saved",
            url: try XCTUnwrap(URL(string: "https://example.com/root")),
            placement: .current
        )
        saved.placement = .saved

        let context = BrowserPageNavigationContext(
            tab: saved,
            spaceID: SpaceID(),
            profileID: UUID()
        )

        XCTAssertEqual(context.savedURL, saved.url)
    }

    func testMovingTabIntoSavedAreaCapturesRootAndNavigationDoesNotReplaceIt() throws {
        var session = BrowserSession.preview
        let destination = try XCTUnwrap(URL(string: "https://example.com/root"))
        let laterURL = try XCTUnwrap(URL(string: "https://example.net/later"))
        let tabID = try XCTUnwrap(
            session.openTab(title: "Root", url: destination)
        )

        XCTAssertTrue(session.moveTab(tabID, to: .saved))
        session.updateSelectedTab(url: laterURL, title: "Later")

        let tab = try XCTUnwrap(session.selectedTab)
        XCTAssertEqual(tab.url, laterURL)
        XCTAssertEqual(tab.savedSiteURL, destination)
    }

    func testOrderedRoutesPrecedeDefaultAndSkipDisabledOrMissingSpaces() throws {
        let suiteName = "BrowserTransientBrowsingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserLinkPreferenceStore(
            defaults: defaults,
            persistenceKey: "links"
        )
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        let url = try XCTUnwrap(URL(string: "https://github.com/crest"))

        store.update { preferences in
            preferences.externalLinkDestination = .quickWindow
            preferences.routes = [
                BrowserLinkRoute(
                    isEnabled: false,
                    match: .contains,
                    pattern: "github.com",
                    destinationSpaceID: personal.id
                ),
                BrowserLinkRoute(
                    match: .contains,
                    pattern: "github.com",
                    destinationSpaceID: work.id
                ),
            ]
        }

        XCTAssertEqual(store.routingDecision(for: url, in: session), .space(work.id))
    }

    func testQuickWindowRemembersSpaceByNormalizedSite() throws {
        let suiteName = "BrowserTransientBrowsingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserLinkPreferenceStore(defaults: defaults, persistenceKey: "links")
        let session = BrowserSession.preview
        let personal = try XCTUnwrap(session.spaces.last)
        let first = try XCTUnwrap(URL(string: "https://www.example.com/first"))
        let second = try XCTUnwrap(URL(string: "https://example.com/second"))

        store.rememberQuickWindowSpace(personal.id, for: first)

        XCTAssertEqual(
            store.routingDecision(for: second, in: session),
            .quickWindow(spaceID: personal.id)
        )
    }

    func testIsolatedLaunchCanResetPersistedLinkRoutes() throws {
        let suiteName = "BrowserTransientBrowsingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserLinkPreferenceStore(
            defaults: defaults,
            persistenceKey: "links"
        )
        let destination = try XCTUnwrap(BrowserSession.preview.spaces.first?.id)
        store.addRoute(destinationSpaceID: destination)
        XCTAssertEqual(store.preferences.routes.count, 1)

        store.reset()

        XCTAssertEqual(store.preferences, .default)
        XCTAssertNil(defaults.data(forKey: "links"))
    }

    func testPeekClickModifierPersistsAndDefaultsToOption() throws {
        let suiteName = "BrowserTransientBrowsingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistenceKey = "links"
        var store: BrowserLinkPreferenceStore? = BrowserLinkPreferenceStore(
            defaults: defaults,
            persistenceKey: persistenceKey
        )

        XCTAssertEqual(store?.preferences.peekClickModifier, .option)
        store?.update { $0.peekClickModifier = .command }
        store = nil

        let restored = BrowserLinkPreferenceStore(
            defaults: defaults,
            persistenceKey: persistenceKey
        )
        XCTAssertEqual(restored.preferences.peekClickModifier, .command)
    }

    func testMovingLinkRoutePersistsOrderAndIgnoresOutOfBoundsMoves() throws {
        let suiteName = "BrowserTransientBrowsingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistenceKey = "links"
        let store = BrowserLinkPreferenceStore(
            defaults: defaults,
            persistenceKey: persistenceKey
        )
        let destination = try XCTUnwrap(BrowserSession.preview.spaces.first?.id)

        store.addRoute(destinationSpaceID: destination)
        store.addRoute(destinationSpaceID: destination)
        let originalOrder = store.preferences.routes.map(\.id)
        XCTAssertEqual(originalOrder.count, 2)

        store.moveRoute(originalOrder[0], by: 1)
        let movedOrder = Array(originalOrder.reversed())
        XCTAssertEqual(store.preferences.routes.map(\.id), movedOrder)

        store.moveRoute(originalOrder[0], by: 1)
        store.moveRoute(originalOrder[1], by: -1)
        XCTAssertEqual(store.preferences.routes.map(\.id), movedOrder)

        let reloaded = BrowserLinkPreferenceStore(
            defaults: defaults,
            persistenceKey: persistenceKey
        )
        XCTAssertEqual(reloaded.preferences.routes.map(\.id), movedOrder)
    }

    func testDismissedQuickWindowArchivesAndRecordsHistoryInExactSpace() throws {
        var session = BrowserSession.preview
        let personal = try XCTUnwrap(session.spaces.last)
        let work = try XCTUnwrap(session.spaces.first)
        let url = try XCTUnwrap(URL(string: "https://example.com/transient"))

        session.archiveTransientPage(url: url, title: "Transient", in: personal.id)
        session.recordVisit(url: url, title: "Transient", in: personal.id)

        XCTAssertEqual(session.space(id: personal.id)?.archivedTabs.last?.reason, .quickWindow)
        XCTAssertEqual(session.space(id: personal.id)?.history.first?.url, url)
        XCTAssertFalse(session.space(id: work.id)?.history.contains(where: { $0.url == url }) == true)
    }

    func testTransientMutationsRejectAReplacementProfileWithTheSameSpaceID() throws {
        let source = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: source)
        let replacement = BrowserSpace(
            id: source.id,
            profile: BrowsingProfile(),
            name: source.name,
            symbol: source.symbol,
            accent: source.accent,
            branding: source.branding,
            folders: source.folders,
            tabs: source.tabs,
            archivedTabs: source.archivedTabs,
            history: [],
            browsingPreferences: source.browsingPreferences,
            credentialPreferences: source.credentialPreferences,
            accessPolicy: source.accessPolicy,
            isSavedTabsExpanded: source.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: source.savedTabsExpansionModifiedAt,
            selectedTabID: source.selectedTabID
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [replacement],
                selectedSpaceID: replacement.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/stale-lease"))

        XCTAssertNil(browser.openNewTab(url: url, matching: assignment))
        XCTAssertFalse(
            browser.recordVisit(
                url: url,
                title: "Stale",
                matching: assignment
            )
        )
        XCTAssertFalse(
            browser.archiveTransientPage(
                url: url,
                title: "Stale",
                matching: assignment
            )
        )
        XCTAssertTrue(browser.session.selectedSpace?.history.isEmpty == true)
        XCTAssertTrue(
            browser.session.selectedSpace?.archivedTabs
                == replacement.archivedTabs
        )
    }

    // MARK: - The shared lease ladder

    func testTransientLeaseDispositionAnswersInLadderOrder() {
        let open = makePolicySpace(name: "Work")
        var locked = makePolicySpace(name: "Private")
        locked.accessPolicy = .deviceOwnerAuthentication
        let access = makeAccessController()

        XCTAssertEqual(
            BrowserTransientSessionPolicy.disposition(
                isPresentingRequest: false,
                space: locked,
                isLocked: access.isLocked
            ),
            .notPresented
        )
        XCTAssertEqual(
            BrowserTransientSessionPolicy.disposition(
                isPresentingRequest: true,
                space: nil,
                isLocked: access.isLocked
            ),
            .sourceMissing
        )
        XCTAssertEqual(
            BrowserTransientSessionPolicy.disposition(
                isPresentingRequest: true,
                space: locked,
                isLocked: access.isLocked
            ),
            .sourceLocked
        )
        XCTAssertEqual(
            BrowserTransientSessionPolicy.disposition(
                isPresentingRequest: true,
                space: open,
                isLocked: access.isLocked
            ),
            .usable(open)
        )
    }

    func testTransientPromotionListsLiveSpacesAndTheRequestsOwnLockedSpace() {
        var lockedSource = makePolicySpace(name: "Source")
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        var lockedOther = makePolicySpace(name: "Private")
        lockedOther.accessPolicy = .deviceOwnerAuthentication
        let open = makePolicySpace(name: "Work")
        let deleting = makePolicySpace(name: "Going")
        let access = makeAccessController()

        let offered = BrowserTransientSessionPolicy.availableSpaces(
            in: [lockedSource, lockedOther, open, deleting],
            deletingSpaceIDs: [deleting.id],
            requestSpaceID: lockedSource.id,
            isLocked: access.isLocked
        )

        XCTAssertEqual(offered.map(\.id), [lockedSource.id, open.id])
    }

    func testTransientLeaseIsReusedOnlyByItsRequestAssignment() {
        let space = makePolicySpace(name: "Source")
        let other = makePolicySpace(name: "Destination")
        let assignment = BrowserSpaceRuntimeAssignment(space: space)

        XCTAssertTrue(
            BrowserTransientSessionPolicy.reusesLease(
                leaseAssignment: assignment,
                requestAssignment: assignment,
                leaseCanBeReused: true
            )
        )
        XCTAssertFalse(
            BrowserTransientSessionPolicy.reusesLease(
                leaseAssignment: assignment,
                requestAssignment: assignment,
                leaseCanBeReused: false
            )
        )
        XCTAssertFalse(
            BrowserTransientSessionPolicy.reusesLease(
                leaseAssignment: assignment,
                requestAssignment: BrowserSpaceRuntimeAssignment(space: other),
                leaseCanBeReused: true
            )
        )
    }

    private func makePolicySpace(name: String) -> BrowserSpace {
        let tab = BrowserTab.startPage()
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func makeAccessController() -> BrowserSpaceAccessController {
        BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
    }
}
