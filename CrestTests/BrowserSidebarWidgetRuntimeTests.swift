import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarWidgetRuntimeTests: XCTestCase {
    func testRegistryOrdersKindsThenInstancesAndShowsEveryProfileTogether() {
        let registry = BrowserSidebarWidgetRegistry(
            registrations: [.nowPlaying, .softwareUpdate]
        )
        let profileID = UUID()
        let otherProfileID = UUID()
        let firstSpace = SpaceID()
        let secondSpace = SpaceID()
        let foreignSpace = SpaceID()
        let first = nowPlayingInstance(
            tabID: TabID(),
            spaceID: firstSpace,
            profileID: profileID,
            ordinal: 2
        )
        let second = nowPlayingInstance(
            tabID: TabID(),
            spaceID: secondSpace,
            profileID: profileID,
            ordinal: 1
        )
        let foreign = nowPlayingInstance(
            tabID: TabID(),
            spaceID: foreignSpace,
            profileID: otherProfileID,
            ordinal: 0
        )
        let update = updateInstance(build: "599")

        let visible = registry.visibleInstances(
            from: [first, foreign, update, second],
            platform: .macOS,
            capabilities: [.persistentSidebar, .mediaSessions, .directSoftwareUpdates]
        )

        XCTAssertEqual(
            visible.map(\.id),
            [update.id, foreign.id, second.id, first.id],
            "Kind order first, then insertion ordinal, with no profile filtering."
        )
        XCTAssertEqual(
            visible.compactMap { instance -> SpaceID? in
                guard case .nowPlaying(let session) = instance.presentation
                else { return nil }
                return session.owner.spaceID
            },
            [foreignSpace, secondSpace, firstSpace],
            "The deck is one global layer: neither the active Space nor the active profile is part of visibility."
        )
    }

    func testRegistryFiltersPlatformCapabilitiesAndSingleInstanceKinds() {
        let registry = BrowserSidebarWidgetRegistry(
            registrations: [.nowPlaying, .softwareUpdate]
        )
        let updates = [updateInstance(build: "1"), updateInstance(build: "2")]

        XCTAssertTrue(
            registry.visibleInstances(
                from: updates,
                platform: .mobile,
                capabilities: [.persistentSidebar, .mediaSessions]
            ).isEmpty,
            "Mobile/App Store surfaces must not expose direct-distribution controls."
        )
        XCTAssertEqual(
            registry.visibleInstances(
                from: updates,
                platform: .macOS,
                capabilities: [.directSoftwareUpdates]
            ).count,
            1,
            "A single-instance registration cannot produce duplicate rows."
        )
    }

    func testRuntimePublishesEveryProfilesWidgetsToOneGlobalDeck() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let home = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: UUID(),
            ordinal: 1
        )
        let work = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: UUID(),
            ordinal: 2
        )

        runtime.activateHost(id: BrowserWindowID(), capabilities: [.mediaSessions])
        await settle()
        source.send([home, work])
        await settle()

        XCTAssertEqual(
            runtime.instances(capabilities: [.mediaSessions]).map(\.id),
            [home.id, work.id],
            "Switching to a Space in another profile never removes the widget layer."
        )
    }

    func testWorkerLifecycleStartsOnceCancelsAtLastHostAndResumesFromAuthority() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let firstWindow = BrowserWindowID()
        let secondWindow = BrowserWindowID()

        runtime.activateHost(id: firstWindow, capabilities: [.mediaSessions])
        await settle()
        XCTAssertTrue(runtime.isWorkerRunning(for: .nowPlaying))
        XCTAssertEqual(source.subscriptionCount, 1)

        runtime.activateHost(id: firstWindow, capabilities: [.mediaSessions])
        runtime.activateHost(id: secondWindow, capabilities: [.mediaSessions])
        await settle()
        XCTAssertEqual(source.subscriptionCount, 1)

        runtime.suspendHost(id: firstWindow)
        XCTAssertTrue(runtime.isWorkerRunning(for: .nowPlaying))
        runtime.suspendHost(id: secondWindow)
        XCTAssertFalse(runtime.isWorkerRunning(for: .nowPlaying))
        await settle()
        XCTAssertEqual(source.terminationCount, 1)

        runtime.activateHost(id: secondWindow, capabilities: [.mediaSessions])
        await settle()
        XCTAssertTrue(runtime.isWorkerRunning(for: .nowPlaying))
        XCTAssertEqual(source.subscriptionCount, 2)
    }

    func testVisibilityPublishesOnlyDistinctStateAndSupportsMultipleInstances() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 1
        )
        let second = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: BrowserWindowID(), capabilities: [.mediaSessions])
        await settle()
        source.send([first, second])
        await settle()
        XCTAssertEqual(runtime.visibilityRevision, 1)
        XCTAssertEqual(
            runtime.instances(capabilities: [.mediaSessions]).map(\.id),
            [first.id, second.id]
        )

        source.send([second, first])
        await settle()
        XCTAssertEqual(
            runtime.visibilityRevision,
            1,
            "Equivalent source emissions must not thrash sidebar layout."
        )

        source.send([])
        await settle()
        XCTAssertEqual(runtime.visibilityRevision, 2)
        XCTAssertTrue(runtime.publishedInstances.isEmpty)
    }

    func testCarouselSelectsNewestInstanceThenPreservesManualChoiceAcrossSpaces() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 1
        )
        let newest = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: BrowserWindowID(), capabilities: [.mediaSessions])
        await settle()
        source.send([first])
        await settle()
        var visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(runtime.carouselSelection, first.id)

        source.send([first, newest])
        await settle()
        visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            newest.id,
            "A newly registered widget becomes the centered carousel card."
        )

        runtime.selectCarouselInstance(
            first.id,
            visibleInstances: visible
        )
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            first.id,
            "One global selection: it does not reset merely because its owner belongs to another Space or profile."
        )
    }

    func testCarouselSelectionPrunesRemovedWidgetsAndFallsBackToARemainingCard() async {
        let source = FakeSidebarWidgetSource(kindID: .nowPlaying)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [source]
        )
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 1
        )
        let second = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 2
        )

        runtime.activateHost(id: BrowserWindowID(), capabilities: [.mediaSessions])
        await settle()
        source.send([first, second])
        await settle()
        var visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        runtime.selectCarouselInstance(
            first.id,
            visibleInstances: visible
        )
        XCTAssertEqual(runtime.carouselSelection, first.id)

        source.send([second])
        await settle()
        XCTAssertNil(
            runtime.carouselSelection,
            "Navigation or tab cleanup removes carousel state for the stale widget identity."
        )

        visible = runtime.instances(capabilities: [.mediaSessions])
        runtime.reconcileCarouselSelection(visibleInstances: visible)
        XCTAssertEqual(
            runtime.carouselSelection,
            second.id,
            "Losing the centered card falls back to a widget that is still visible."
        )
    }

    func testCarouselAdjacencyStopsAtBounds() {
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 1
        )
        let second = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 2
        )
        let instances = [first, second]

        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.adjacentID(
                to: first.id,
                in: instances,
                direction: .previous
            ),
            first.id
        )
        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.adjacentID(
                to: first.id,
                in: instances,
                direction: .next
            ),
            second.id
        )
        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.adjacentID(
                to: second.id,
                in: instances,
                direction: .next
            ),
            second.id
        )
    }

    func testCyclicAdjacencyWrapsAtBothEndsOfTheDeck() {
        let profileID = UUID()
        let first = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 1
        )
        let second = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 2
        )
        let third = nowPlayingInstance(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: profileID,
            ordinal: 3
        )
        let instances = [first, second, third]

        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.cyclicAdjacentID(
                to: third.id,
                in: instances,
                direction: .next
            ),
            first.id,
            "The deck flips past its last card back to the first."
        )
        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.cyclicAdjacentID(
                to: first.id,
                in: instances,
                direction: .previous
            ),
            third.id,
            "Flipping back from the first card lands on the last."
        )
        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.cyclicAdjacentID(
                to: first.id,
                in: instances,
                direction: .next
            ),
            second.id
        )
        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.cyclicAdjacentID(
                to: first.id,
                in: [first],
                direction: .next
            ),
            first.id,
            "A one-card deck cannot flip away from itself."
        )
        XCTAssertNil(
            BrowserSidebarWidgetCarouselPolicy.cyclicAdjacentID(
                to: nil,
                in: [],
                direction: .next
            )
        )
    }

    func testDeckOrderStartsAtTheSelectedCardAndWrapsToFillVisibleDepth() {
        let profileID = UUID()
        let instances = (1...4).map { ordinal in
            nowPlayingInstance(
                tabID: TabID(),
                spaceID: SpaceID(),
                profileID: profileID,
                ordinal: UInt64(ordinal)
            )
        }

        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.deckOrder(
                from: instances[3].id,
                in: instances,
                visibleDepth: 3
            ).map(\.id),
            [instances[3].id, instances[0].id, instances[1].id],
            "The cards behind the selected one are the cards it will flip to."
        )
        XCTAssertEqual(
            BrowserSidebarWidgetCarouselPolicy.deckOrder(
                from: instances[0].id,
                in: Array(instances.prefix(2)),
                visibleDepth: 3
            ).count,
            2,
            "A deck never repeats a card to fill an empty slot."
        )
        XCTAssertTrue(
            BrowserSidebarWidgetCarouselPolicy.deckOrder(
                from: nil,
                in: [],
                visibleDepth: 3
            ).isEmpty
        )
    }

    func testScrollAccumulatorFlipsOncePerPhasedTrackpadFlick() {
        var accumulator = BrowserSidebarWidgetDeckScrollAccumulator()
        let threshold = BrowserSidebarWidgetDeckScrollAccumulator.continuousThreshold

        XCTAssertNil(
            accumulator.consume(
                continuous(deltaY: -threshold / 3, at: 0, beginsGesture: true)
            ),
            "A flick below the threshold has not committed to a card yet."
        )
        XCTAssertNil(
            accumulator.consume(continuous(deltaY: -threshold / 3, at: 0.01))
        )
        XCTAssertEqual(
            accumulator.consume(continuous(deltaY: -threshold / 3, at: 0.02)),
            .next
        )
        XCTAssertNil(
            accumulator.consume(continuous(deltaY: -threshold * 4, at: 0.03)),
            "The rest of one flick cannot advance a second card."
        )
        XCTAssertNil(
            accumulator.consume(
                continuous(deltaY: -threshold * 4, at: 0.04, isMomentum: true)
            ),
            "The momentum tail advances nothing."
        )

        XCTAssertNil(accumulator.consume(continuous(deltaY: 0, at: 0.2, endsGesture: true)))
        XCTAssertEqual(
            accumulator.consume(continuous(deltaY: threshold, at: 0.21, beginsGesture: true)),
            .previous,
            "The next flick starts from a cleared accumulator."
        )
    }

    func testScrollAccumulatorSegmentsAPhaselessStreamAndNeverLatchesForever() {
        var accumulator = BrowserSidebarWidgetDeckScrollAccumulator()
        let threshold = BrowserSidebarWidgetDeckScrollAccumulator.continuousThreshold
        let gap = BrowserSidebarWidgetDeckScrollAccumulator.gestureGap

        // A Magic Mouse delivers precise deltas with no phase at all.
        XCTAssertEqual(
            accumulator.consume(continuous(deltaY: -threshold, at: 1)),
            .next
        )
        XCTAssertNil(
            accumulator.consume(continuous(deltaY: -threshold, at: 1 + gap / 2)),
            "Inside one gesture window the latch still holds a single flip."
        )
        XCTAssertEqual(
            accumulator.consume(continuous(deltaY: -threshold, at: 1 + gap * 1.1)),
            .next,
            "The latch expires as a rate limit, so a sustained scroll keeps advancing."
        )
        XCTAssertEqual(
            accumulator.consume(continuous(deltaY: threshold, at: 10)),
            .previous,
            "A quiet gap starts a fresh gesture even though no phase ever arrives."
        )
    }

    func testScrollAccumulatorTreatsWheelNotchesAsOneCardEachWithARateLimit() {
        var accumulator = BrowserSidebarWidgetDeckScrollAccumulator()
        let interval = BrowserSidebarWidgetDeckScrollAccumulator.discreteInterval

        XCTAssertEqual(
            accumulator.consume(
                BrowserSidebarWidgetDeckScrollInput(deltaY: -1, timestamp: 0, isPrecise: false)
            ),
            .next,
            "One wheel notch is one card; a notch never has to clear a pixel threshold."
        )
        XCTAssertNil(
            accumulator.consume(
                BrowserSidebarWidgetDeckScrollInput(
                    deltaY: -1,
                    timestamp: interval / 2,
                    isPrecise: false
                )
            )
        )
        XCTAssertEqual(
            accumulator.consume(
                BrowserSidebarWidgetDeckScrollInput(
                    deltaY: 1,
                    timestamp: interval * 1.1,
                    isPrecise: false
                )
            ),
            .previous
        )
    }

    private func continuous(
        deltaY: CGFloat,
        at timestamp: TimeInterval,
        beginsGesture: Bool = false,
        endsGesture: Bool = false,
        isMomentum: Bool = false
    ) -> BrowserSidebarWidgetDeckScrollInput {
        BrowserSidebarWidgetDeckScrollInput(
            deltaY: deltaY,
            timestamp: timestamp,
            isPrecise: true,
            beginsGesture: beginsGesture,
            endsGesture: endsGesture,
            isMomentum: isMomentum
        )
    }

    func testDeckDragTracksPartiallyAndRubberBandsBeyondItsLimit() {
        let limit = BrowserSidebarWidgetDeckStyle.dragRubberBandLimit
        let tracked = BrowserSidebarWidgetDeckStyle.draggedOffset(
            forTranslation: 40
        )

        XCTAssertEqual(
            tracked,
            40 * BrowserSidebarWidgetDeckStyle.dragTrackingFactor,
            accuracy: 0.001,
            "Inside the limit the card follows a fraction of the finger."
        )
        let far = BrowserSidebarWidgetDeckStyle.draggedOffset(forTranslation: 4_000)
        XCTAssertGreaterThan(far, limit)
        XCTAssertLessThan(
            far,
            limit * 2,
            "A long drag can never slide the deck out of the sidebar."
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckStyle.draggedOffset(forTranslation: -4_000),
            -far,
            accuracy: 0.001,
            "Rubber banding is symmetric in both directions."
        )
    }

    func testDeckDragCommitsOnTravelOrFlickAndOtherwiseSpringsBack() {
        let threshold = BrowserSidebarWidgetDeckStyle.dragCommitThreshold

        XCTAssertNil(
            BrowserSidebarWidgetDeckStyle.dragCommitDirection(
                translation: threshold - 1,
                predictedEndTranslation: threshold - 1
            ),
            "A short drag returns the front card to its slot."
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckStyle.dragCommitDirection(
                translation: -threshold,
                predictedEndTranslation: -threshold
            ),
            .next,
            "Swiping the front card left advances the deck."
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckStyle.dragCommitDirection(
                translation: threshold,
                predictedEndTranslation: threshold
            ),
            .previous
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckStyle.dragCommitDirection(
                translation: 4,
                predictedEndTranslation: -(threshold + 40)
            ),
            .next,
            "A fast flick commits on its predicted travel, not the distance held."
        )
    }

    func testSideStepperNeverConsumesCardWidth() {
        let singleCardInsets = BrowserSidebarWidgetCarouselLayoutPolicy.cardInsets(
            instanceCount: 1
        )
        let multipleCardInsets = BrowserSidebarWidgetCarouselLayoutPolicy.cardInsets(
            instanceCount: 12
        )
        XCTAssertEqual(singleCardInsets, .zero)
        XCTAssertEqual(multipleCardInsets, singleCardInsets)
        XCTAssertEqual(
            BrowserSidebarWidgetDeckStyle.sideStepperExternalOffset,
            BrowserSidebarWidgetDeckStyle.sideStepperOffset(
                cardTrailingInset: CrestSpacing.small,
                railWidth: BrowserSidebarWidgetDeckStyle.sideStepperRailWidth,
                paneBoundaryWidth: CrestLayout.hairline
            )
        )

        let hostTrailingEdge: CGFloat = 300
        let cardTrailingEdge = hostTrailingEdge - CrestSpacing.small
        let webpageLeadingEdge = hostTrailingEdge + CrestLayout.hairline
        let railCenter =
            hostTrailingEdge
            - BrowserSidebarWidgetDeckStyle.sideStepperRailWidth / 2
            + BrowserSidebarWidgetDeckStyle.sideStepperExternalOffset
        XCTAssertEqual(
            railCenter,
            (cardTrailingEdge + webpageLeadingEdge) / 2,
            "The rail center is derived from the card and webpage edges."
        )
    }

    func testSideStepperSelectionDoesNotChangeDotGeometry() {
        let selectedSize = BrowserSidebarWidgetDeckStyle.indicatorSize(
            isSelected: true
        )
        let unselectedSize = BrowserSidebarWidgetDeckStyle.indicatorSize(
            isSelected: false
        )

        XCTAssertEqual(selectedSize, unselectedSize)
        XCTAssertEqual(
            selectedSize,
            CGSize(
                width: BrowserSidebarWidgetDeckStyle.indicatorDotDiameter,
                height: BrowserSidebarWidgetDeckStyle.indicatorDotDiameter
            )
        )
        XCTAssertLessThan(
            BrowserSidebarWidgetDeckStyle.indicatorDotHitHeight,
            BrowserSidebarWidgetDeckStyle.indicatorHitHeight,
            "The dot group stays compact while the overflow step controls retain their larger targets."
        )
    }

    func testDesktopDeckDragTracksTheHorizontalAxis() {
        XCTAssertEqual(
            BrowserSidebarWidgetDeckGesturePolicy.currentPlatformAxis,
            .horizontal
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckGesturePolicy.primaryTranslation(
                horizontal: 40,
                vertical: -70,
                axis: .horizontal
            ),
            40
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckGesturePolicy.cardOffset(
                trackedTranslation: 12,
                slotOffset: 6,
                axis: .horizontal
            ),
            CGSize(width: 12, height: 6)
        )
    }

    func testOnlyRecedingCardsFadeTheirContentBehindTheFrontCard() {
        XCTAssertFalse(
            BrowserSidebarWidgetDeckStyle.masksContent(forDepth: 0),
            "The front card's content is never masked, so its controls stay whole and hit-testable."
        )
        XCTAssertTrue(BrowserSidebarWidgetDeckStyle.masksContent(forDepth: 1))
        XCTAssertTrue(BrowserSidebarWidgetDeckStyle.masksContent(forDepth: 2))

        XCTAssertEqual(BrowserSidebarWidgetDeckStyle.contentOpacity(forDepth: 0), 1)
        XCTAssertLessThan(
            BrowserSidebarWidgetDeckStyle.contentOpacity(forDepth: 1),
            1,
            "A receding card's content fades rather than popping out of the deck."
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckStyle.contentOpacity(forDepth: 2),
            0,
            "The deepest slot shows card stock only."
        )
        XCTAssertLessThan(
            BrowserSidebarWidgetDeckStyle.contentMaskFadeEnd,
            1,
            "The fade must finish above the clip edge, not at it."
        )
        XCTAssertLessThan(
            BrowserSidebarWidgetDeckStyle.contentMaskFadeStart,
            BrowserSidebarWidgetDeckStyle.contentMaskFadeEnd
        )
    }

    func testDeckSlotOffsetKeepsAPredictablePeekUnderTheFrontCard() {
        let peek = BrowserSidebarWidgetDeckStyle.layerPeek
        let height: CGFloat = 120

        XCTAssertEqual(
            BrowserSidebarWidgetDeckStyle.slotOffset(forDepth: 0, cardHeight: height),
            0
        )
        for depth in 1...2 {
            let offset = BrowserSidebarWidgetDeckStyle.slotOffset(
                forDepth: depth,
                cardHeight: height
            )
            let scale = BrowserSidebarWidgetDeckStyle.scale(forDepth: depth)
            XCTAssertEqual(
                offset + height * scale - height,
                peek * CGFloat(depth),
                accuracy: 0.001,
                "Each under-card peeks one layer below the front card regardless of scale."
            )
        }
    }

    func testCarouselHeightTracksOnlyMeaningfulSelectedCardChanges() {
        XCTAssertFalse(
            BrowserSidebarWidgetCarouselLayoutPolicy.shouldUpdateActiveCardHeight(
                currentHeight: 52,
                measuredHeight: 104,
                isSelected: false
            )
        )
        XCTAssertFalse(
            BrowserSidebarWidgetCarouselLayoutPolicy.shouldUpdateActiveCardHeight(
                currentHeight: 52,
                measuredHeight: 52.25,
                isSelected: true
            )
        )
        XCTAssertTrue(
            BrowserSidebarWidgetCarouselLayoutPolicy.shouldUpdateActiveCardHeight(
                currentHeight: 52,
                measuredHeight: 104,
                isSelected: true
            )
        )
        XCTAssertTrue(
            BrowserSidebarWidgetCarouselLayoutPolicy.shouldUpdateActiveCardHeight(
                currentHeight: nil,
                measuredHeight: 52,
                isSelected: true
            )
        )
    }

    private func nowPlayingInstance(
        tabID: TabID,
        spaceID: SpaceID,
        profileID: UUID,
        ordinal: UInt64
    ) -> BrowserSidebarWidgetInstance {
        let sessionID = BrowserMediaSessionID(
            tabID: tabID,
            documentIdentifier: "document-\(ordinal)"
        )
        let snapshot = BrowserMediaSessionSnapshot(
            id: sessionID,
            owner: BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: spaceID,
                profileID: profileID
            ),
            ownerTitle: "Owner Tab \(ordinal)",
            title: "Track \(ordinal)",
            artist: nil,
            album: nil,
            artworkData: nil,
            playbackState: .playing,
            isAudible: true,
            isMuted: false,
            availableActions: [.pause],
            orderingOrdinal: ordinal
        )
        return BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .nowPlaying,
                instanceID: sessionID.id
            ),
            scope: .profile(profileID),
            orderingOrdinal: ordinal,
            presentation: .nowPlaying(snapshot),
            availableActions: [.activateOwner, .pause]
        )
    }

    private func updateInstance(build: String) -> BrowserSidebarWidgetInstance {
        BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .softwareUpdate,
                instanceID: build
            ),
            scope: .application,
            orderingOrdinal: 0,
            presentation: .softwareUpdate(
                BrowserSoftwareUpdateWidgetSnapshot(
                    phase: .available,
                    title: "Crest Update",
                    version: "0.5.0",
                    build: build,
                    releaseNotes: nil,
                    informationURL: nil,
                    message: nil,
                    progress: nil,
                    isInformationOnly: false,
                    allowsInstallation: true,
                    allowsSkipping: true,
                    allowsCancellation: false,
                    allowsInstallAndRelaunch: false,
                    allowsInstallationRetry: false,
                    isFixture: true
                )
            ),
            availableActions: [.installUpdate, .dismissExactUpdate]
        )
    }

    private func settle() async {
        for _ in 0..<4 { await Task.yield() }
    }
}

@MainActor
private final class FakeSidebarWidgetSource: BrowserSidebarWidgetEventSource {
    let kindID: BrowserSidebarWidgetKindID
    private(set) var subscriptionCount = 0
    private(set) var terminationCount = 0
    private var current: [BrowserSidebarWidgetInstance] = []
    private var continuations: [UUID: AsyncStream<[BrowserSidebarWidgetInstance]>.Continuation] = [:]

    init(kindID: BrowserSidebarWidgetKindID) {
        self.kindID = kindID
    }

    func events() -> AsyncStream<[BrowserSidebarWidgetInstance]> {
        subscriptionCount += 1
        let id = UUID()
        let (stream, continuation) = AsyncStream<[BrowserSidebarWidgetInstance]>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        continuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                continuations[id] = nil
                terminationCount += 1
            }
        }
        continuation.yield(current)
        return stream
    }

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {}

    func send(_ instances: [BrowserSidebarWidgetInstance]) {
        current = instances
        for continuation in continuations.values {
            continuation.yield(instances)
        }
    }
}
