import AppKit
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class SpaceScrollGestureTests: XCTestCase {
    func testOneHorizontalIntentPerGesturePreservesVerticalAndOutsideScrolling() {
        struct Event {
            let input: SpaceScrollGesturePolicy.Input
            var isInside = true
        }
        struct Scenario {
            let name: String
            let events: [Event]
            let decisions: [SpaceScrollGesturePolicy.Decision]
        }

        let scenarios: [Scenario] = [
            Scenario(
                name: "Long phased gesture and momentum never repeat, then a fresh gesture can step",
                events: [
                    Event(input: input(-100, at: 0, phase: .began)),
                    Event(input: input(-100, at: 1, phase: .changed)),
                    Event(input: input(100, at: 2, phase: .changed)),
                    Event(input: input(0, at: 2.1, phase: .ended), isInside: false),
                    Event(input: input(-100, at: 2.2, momentum: true), isInside: false),
                    Event(input: input(-100, at: 3, momentum: true), isInside: false),
                    Event(input: input(100, at: 3.1, phase: .began)),
                ],
                decisions: [.step(.next), .consumed, .consumed, .consumed, .consumed, .consumed, .step(.previous)]
            ),
            Scenario(
                name: "Vertical axis stays native even when later deltas lean horizontally",
                events: [
                    Event(input: input(1, y: 100, at: 0, phase: .began)),
                    Event(input: input(-150, y: 1, at: 0.1, phase: .changed)),
                    Event(input: input(0, at: 0.2, phase: .ended)),
                    Event(input: input(-100, at: 0.3, momentum: true)),
                    Event(input: input(-100, at: 0.4, phase: .began)),
                ],
                decisions: [.passThrough, .passThrough, .passThrough, .passThrough, .step(.next)]
            ),
            Scenario(
                name: "Phase-less continuous burst rearms only after an idle gap",
                events: [
                    Event(input: input(-100, at: 0)),
                    Event(input: input(-100, at: 0.2)),
                    Event(input: input(-100, at: 0.4)),
                    Event(input: input(100, at: 0.6)),
                    Event(input: input(100, at: 0.8)),
                    Event(input: input(100, at: 2)),
                ],
                decisions: [.step(.next), .consumed, .consumed, .consumed, .consumed, .step(.previous)]
            ),
            Scenario(
                name: "Wheel notches use their own units and one step per burst",
                events: [
                    Event(input: input(-1, at: 0, precise: false)),
                    Event(input: input(-10, at: 0.05, precise: false)),
                    Event(input: input(1, at: 0.1, precise: false)),
                    Event(input: input(1, at: 1, precise: false)),
                ],
                decisions: [.step(.next), .consumed, .consumed, .step(.previous)]
            ),
            Scenario(
                name: "Returning across the origin before acceptance cancels without a compensating step",
                events: [
                    Event(input: input(-20, at: 0, phase: .began)),
                    Event(input: input(40, at: 0.1, phase: .changed)),
                    Event(input: input(-200, at: 0.2, phase: .changed)),
                    Event(input: input(0, at: 0.3, phase: .cancelled)),
                    Event(input: input(-100, at: 0.4, phase: .began)),
                ],
                decisions: [.consumed, .consumed, .consumed, .consumed, .step(.next)]
            ),
            Scenario(
                name: "A gesture starting outside stays untouched, and a later inside gesture works",
                events: [
                    Event(input: input(-100, at: 0, phase: .began), isInside: false),
                    Event(input: input(-100, at: 0.1, phase: .changed)),
                    Event(input: input(0, at: 0.2, phase: .ended)),
                    Event(input: input(-100, at: 0.3, phase: .began)),
                    Event(input: input(0, at: 0.4, phase: .ended)),
                    Event(input: input(100, at: 0.5, phase: .began), isInside: false),
                ],
                decisions: [.passThrough, .passThrough, .passThrough, .step(.next), .consumed, .passThrough]
            ),
            Scenario(
                name: "Momentum without a recognized horizontal gesture passes through",
                events: [
                    Event(input: input(-100, at: 0, momentum: true)),
                    Event(input: input(-100, at: 0.1, momentum: true)),
                    Event(input: input(-100, at: 0.2, phase: .began)),
                ],
                decisions: [.passThrough, .passThrough, .step(.next)]
            ),
        ]

        for scenario in scenarios {
            XCTContext.runActivity(named: scenario.name) { _ in
                var policy = SpaceScrollGesturePolicy()
                let actual = scenario.events.map { policy.consume($0.input, isInside: $0.isInside) }
                XCTAssertEqual(actual, scenario.decisions)
            }
        }
    }

    func testNativeScrollNormalizationPreservesTerminalMomentumUnitsAndLayoutDirection() throws {
        let scroll = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -100, wheel3: 0)
        )
        scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.began.rawValue))
        let began = try XCTUnwrap(NSEvent(cgEvent: scroll))
        let leftToRight = SpaceScrollGestureEventAdapter.input(for: began, layoutDirection: .leftToRight)
        let rightToLeft = SpaceScrollGestureEventAdapter.input(for: began, layoutDirection: .rightToLeft)
        XCTAssertTrue(leftToRight.isPrecise)
        XCTAssertEqual(leftToRight.phase, .began)
        XCTAssertEqual(rightToLeft.deltaX, -leftToRight.deltaX)
        let adapter = SpaceScrollGestureEventAdapter()
        var steps: [BrowserSpaceSwipeDirection] = []
        XCTAssertNil(adapter.handle(began, isInside: true, layoutDirection: .leftToRight) { steps.append($0) })
        XCTAssertEqual(steps, [.next])
        let rtlAdapter = SpaceScrollGestureEventAdapter()
        var rtlSteps: [BrowserSpaceSwipeDirection] = []
        XCTAssertNil(rtlAdapter.handle(began, isInside: true, layoutDirection: .rightToLeft) { rtlSteps.append($0) })
        XCTAssertEqual(rtlSteps, [.previous])

        scroll.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
        scroll.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        scroll.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.ended.rawValue))
        let endedEvent = try XCTUnwrap(NSEvent(cgEvent: scroll))
        let ended = SpaceScrollGestureEventAdapter.input(for: endedEvent, layoutDirection: .leftToRight)
        XCTAssertEqual(ended.deltaX, 0)
        XCTAssertEqual(ended.phase, .ended)
        XCTAssertNil(adapter.handle(endedEvent, isInside: false, layoutDirection: .leftToRight) { steps.append($0) })

        scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        scroll.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(CGMomentumScrollPhase.begin.rawValue))
        let momentumEvent = try XCTUnwrap(NSEvent(cgEvent: scroll))
        let momentum = SpaceScrollGestureEventAdapter.input(for: momentumEvent, layoutDirection: .leftToRight)
        XCTAssertTrue(momentum.isMomentum)
        XCTAssertNil(
            adapter.handle(momentumEvent, isInside: false, layoutDirection: .leftToRight) { steps.append($0) })
        XCTAssertEqual(steps, [.next])

        let wheel = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 0, wheel3: 0)
        )
        let verticalEvent = try XCTUnwrap(NSEvent(cgEvent: wheel))
        let vertical = SpaceScrollGestureEventAdapter.input(for: verticalEvent, layoutDirection: .leftToRight)
        XCTAssertFalse(vertical.isPrecise)
        adapter.reset()
        XCTAssertTrue(
            adapter.handle(verticalEvent, isInside: true, layoutDirection: .leftToRight) { steps.append($0) }
                === verticalEvent)

        // A disabled beginning still belongs to that stream after unlocking.
        // Likewise, disabling an accepted stream cannot create a second step.
        let guardedAdapter = SpaceScrollGestureEventAdapter()
        var guardedSteps: [BrowserSpaceSwipeDirection] = []
        let guardedScroll = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -100, wheel3: 0)
        )
        guardedScroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.began.rawValue))
        let guardedBegin = try XCTUnwrap(NSEvent(cgEvent: guardedScroll))
        XCTAssertTrue(
            guardedAdapter.handle(guardedBegin, isInside: true, layoutDirection: .leftToRight, isEnabled: false) {
                guardedSteps.append($0)
            } === guardedBegin)
        let guardedChangeScroll = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -100, wheel3: 0)
        )
        guardedChangeScroll.setIntegerValueField(
            .scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.changed.rawValue))
        let guardedChange = try XCTUnwrap(NSEvent(cgEvent: guardedChangeScroll))
        XCTAssertTrue(
            guardedAdapter.handle(guardedChange, isInside: true, layoutDirection: .leftToRight) {
                guardedSteps.append($0)
            } === guardedChange)
        XCTAssertEqual(guardedSteps, [])
        XCTAssertNil(
            guardedAdapter.handle(guardedBegin, isInside: true, layoutDirection: .leftToRight) {
                guardedSteps.append($0)
            })
        XCTAssertEqual(guardedSteps, [.next])
        guardedAdapter.cancelCurrentGesture()
        XCTAssertTrue(
            guardedAdapter.handle(guardedChange, isInside: true, layoutDirection: .leftToRight, isEnabled: false) {
                guardedSteps.append($0)
            } === guardedChange)
        XCTAssertTrue(
            guardedAdapter.handle(guardedChange, isInside: true, layoutDirection: .leftToRight) {
                guardedSteps.append($0)
            } === guardedChange)
        XCTAssertEqual(guardedSteps, [.next])
        XCTAssertNil(
            guardedAdapter.handle(guardedBegin, isInside: true, layoutDirection: .leftToRight) {
                guardedSteps.append($0)
            })
        XCTAssertEqual(guardedSteps, [.next, .next])
    }

    func testNativePagingTracksPointsAndSettlesBeforeCommitting() async throws {
        var spaces = nativeSpaces()
        var selections: [SpaceID] = []
        var settlements: [SpaceID] = []
        var actualSelection = spaces[0].id
        var acceptsSelection = true
        let (window, viewport) = makeNativeViewport()
        let presentation = SpacePagerPresentation()
        defer {
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        func update(selected: SpaceID) {
            actualSelection = selected
            viewport.update(
                spaces: spaces, selectedSpaceID: selected, isInteractionLocked: false,
                reduceMotion: false, layoutDirection: .leftToRight,
                presentation: presentation,
                selectSpace: {
                    selections.append($0)
                    if acceptsSelection { actualSelection = $0 }
                    return actualSelection
                }, settledSpace: { settlements.append($0) },
                makeRoot: nativeRoot)
        }
        update(selected: spaces[0].id)
        viewport.layoutSubtreeIfNeeded()
        assertPageFrames(viewport, spaces: spaces, selectedIndex: 0)
        let source = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[0].id
            })
        let token = try XCTUnwrap(viewport.beginInteractiveMotion())
        var distance: CGFloat = 0
        for delta in [CGFloat(-3), -17, -90, 12] {
            distance += delta
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: delta, token: token))
            XCTAssertEqual(source.frame.minX, distance, accuracy: 0.001)
            XCTAssertEqual(
                try XCTUnwrap(presentation.snapshot).position, -distance / viewport.bounds.width,
                accuracy: 0.000_001)
            XCTAssertEqual(presentation.snapshot?.phase, .tracking)
        }
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertTrue(settlements.isEmpty)

        // A short, fast flick can finish a page without first dragging halfway.
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -1200, cancelled: false, token: token))
        XCTAssertTrue(selections.isEmpty, "Finger release must not interrupt the settling frames")
        XCTAssertEqual(presentation.snapshot?.phase, .settling)
        XCTAssertEqual(
            try XCTUnwrap(presentation.snapshot).position, -distance / viewport.bounds.width,
            accuracy: 0.000_001)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id])
        XCTAssertEqual(settlements, [spaces[1].id])
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 1)
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -1200, cancelled: false, token: token))
        XCTAssertEqual(selections, [spaces[1].id])
        XCTAssertEqual(settlements, [spaces[1].id])

        // The native selection receipt can precede SwiftUI reconciliation.
        // Returning immediately must still undo the accepted B selection.
        let returning = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 224, token: returning))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 500, cancelled: false, token: returning))
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id, spaces[0].id])
        XCTAssertEqual(actualSelection, spaces[0].id)
        update(selected: spaces[0].id)
        viewport.step(.next)
        try await awaitSettlement(viewport)
        update(selected: spaces[1].id)
        XCTAssertEqual(selections, [spaces[1].id, spaces[0].id, spaces[1].id])

        update(selected: spaces[1].id)
        window.setContentSize(NSSize(width: 321, height: 501))
        viewport.layoutSubtreeIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        assertPageFrames(viewport, spaces: spaces, selectedIndex: 1)
        window.setContentSize(NSSize(width: 320, height: 500))
        viewport.layoutSubtreeIfNeeded()

        let cancelled = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 64, token: cancelled))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 1000, cancelled: true, token: cancelled))
        XCTAssertNotNil(viewport.motion, "Cancellation must settle back instead of snapping at finger release")
        try await awaitSettlement(viewport)
        XCTAssertEqual(
            selections, [spaces[1].id, spaces[0].id, spaces[1].id],
            "Cancellation must not select a different Space")

        acceptsSelection = false
        let refused = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -240, token: refused))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: false, token: refused))
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id, spaces[0].id, spaces[1].id, spaces[2].id])
        XCTAssertEqual(viewport.selectedSpaceID, spaces[1].id)
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertNotNil(viewport.beginInteractiveMotion(), "A refused selection must not leave the viewport locked")

        // Consecutive commands may admit a new neighbor before SwiftUI delivers
        // the first selection receipt. It must enter from beside the live page.
        spaces = nativeSpaces()
        acceptsSelection = true
        update(selected: spaces[0].id)
        viewport.step(.next)
        try await awaitSettlement(viewport)
        viewport.step(.next)
        let incoming = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertGreaterThan(
            try XCTUnwrap(incoming.layer?.presentation()).frame.minX, viewport.bounds.width / 2,
            "A newly admitted page must animate in from its adjacent position")
        try await awaitSettlement(viewport)
        XCTAssertEqual(Array(selections.suffix(2)), [spaces[1].id, spaces[2].id])
    }

    func testNativePagingPreservesInterruptedPositionAndRejectsInvalidatedGestures() async throws {
        var spaces = nativeSpaces()
        var selections: [SpaceID] = []
        var renderedRoots: [SpaceID: (isSelected: Bool, name: String, accessPolicy: BrowserSpaceAccessPolicy)] = [:]
        let (window, viewport) = makeNativeViewport()
        let presentation = SpacePagerPresentation()
        defer {
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        func update(selected: SpaceID, locked: Bool = false) {
            viewport.update(
                spaces: spaces, selectedSpaceID: selected, isInteractionLocked: locked,
                reduceMotion: false, layoutDirection: .leftToRight,
                presentation: presentation,
                selectSpace: {
                    selections.append($0)
                    return $0
                }, settledSpace: { _ in },
                makeRoot: { space, isSelected in
                    renderedRoots[space.id] = (isSelected, space.name, space.accessPolicy)
                    return self.nativeRoot(space, isSelected)
                })
        }
        update(selected: spaces[0].id)
        viewport.layoutSubtreeIfNeeded()
        let source = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[0].id
            })
        let first = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -224, token: first))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: first))
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        let sourceLayer = try XCTUnwrap(source.layer)
        let before = (sourceLayer.presentation() ?? sourceLayer).frame.minX
        let second = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertEqual(source.frame.minX, before, accuracy: 0.5)
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: first))

        // A new leftward gesture starts from the inherited rightward offset of
        // the incoming page. Its first point must not clamp that offset to zero.
        let inherited = source.frame.minX
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -1, token: second))
        XCTAssertEqual(source.frame.minX, inherited - 1, accuracy: 0.001)
        viewport.layoutSubtreeIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            (sourceLayer.presentation() ?? sourceLayer).frame.minX, inherited - 1, accuracy: 0.5,
            "An interrupted animation must stay stopped after AppKit layout and the next frame")
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -255, token: second))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -900, cancelled: false, token: second))
        XCTAssertTrue(selections.isEmpty)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[2].id])
        update(selected: spaces[2].id)

        let superseded = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 128, token: superseded))
        update(selected: spaces[0].id)
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertNil(viewport.motion, "A distant direct selection must not leave a compressed strip to interrupt")
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: 1000, cancelled: false, token: superseded))
        update(selected: spaces[0].id, locked: true)
        XCTAssertNil(viewport.beginInteractiveMotion())
        XCTAssertEqual(viewport.presentationSpaceID, spaces[0].id)
        XCTAssertEqual(selections, [spaces[2].id])

        update(selected: spaces[0].id)
        let edge = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 39, token: edge))
        let beforeLastPoint = source.frame.minX
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 1, token: edge))
        XCTAssertGreaterThan(source.frame.minX, beforeLastPoint)
        let releasePosition = source.frame.minX
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 1000, cancelled: false, token: edge))
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        let edgePosition = (sourceLayer.presentation() ?? sourceLayer).frame.minX
        XCTAssertGreaterThanOrEqual(edgePosition, -0.5)
        XCTAssertLessThanOrEqual(edgePosition, releasePosition + 0.5, "Release must move directly toward the endpoint")
        let edgeRestart = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertEqual(source.frame.minX, edgePosition, accuracy: 0.5)
        let inheritedEdge = source.frame.minX
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 1, token: edgeRestart))
        XCTAssertGreaterThan(
            source.frame.minX, inheritedEdge,
            "Continuing edge travel must not apply resistance twice and jump backward")
        let restartedEdgePosition = source.frame.minX
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: true, token: edgeRestart))
        try await assertDirectSettlement(viewport, host: source, start: restartedEdgePosition, endpoint: 0)
        XCTAssertEqual(selections, [spaces[2].id])

        viewport.step(.next)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[2].id, spaces[1].id])
        // An external selection supersedes the pending B receipt, even when
        // SwiftUI never delivered that intermediate selection to the viewport.
        update(selected: spaces[2].id)
        try await awaitSettlement(viewport)
        let activeHost = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        XCTAssertFalse(activeHost.isAccessibilityHidden())

        // Command slides reuse ready roots; completion receives the latest
        // content and role even if another update arrives during the animation.
        update(selected: spaces[0].id)
        update(selected: spaces[1].id)
        XCTAssertNotNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.isSelected, false)
        spaces[1].name = "Changed while settling"
        update(selected: spaces[1].id)
        try await awaitSettlement(viewport)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.isSelected, true)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.name, spaces[1].name)

        // Resize and detachment can bypass the animation's completion. They
        // must still refresh the authoritative page before returning input.
        update(selected: spaces[2].id)
        XCTAssertNotNil(viewport.motion)
        spaces[2].name = "Changed before resize"
        update(selected: spaces[2].id)
        window.setContentSize(NSSize(width: 321, height: 501))
        viewport.layoutSubtreeIfNeeded()
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[2].id]?.isSelected, true)
        XCTAssertEqual(renderedRoots[spaces[2].id]?.name, spaces[2].name)
        update(selected: spaces[1].id)
        XCTAssertNotNil(viewport.motion)
        spaces[1].name = "Changed before reattachment"
        update(selected: spaces[1].id)
        window.contentView = nil
        window.contentView = viewport
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.isSelected, true)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.name, spaces[1].name)

        // A privacy-policy change supersedes both a simultaneous command and
        // an existing physical gesture; an old open-policy root cannot linger.
        spaces[0].accessPolicy = .deviceOwnerAuthentication
        update(selected: spaces[0].id)
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[0].id]?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertEqual(renderedRoots[spaces[0].id]?.isSelected, true)
        let protected = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -32, token: protected))
        spaces[1].accessPolicy = .deviceOwnerAuthentication
        update(selected: spaces[0].id)
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: protected))

        update(selected: spaces[2].id)
        let detached = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 64, token: detached))
        window.contentView = nil
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 2)
        window.contentView = viewport
        let tornDown = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 64, token: tornDown))
        viewport.teardown()
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 2)
        XCTAssertEqual(selections, [spaces[2].id, spaces[1].id])
    }

    func testRepeatedSwipeInterruptionsKeepVisiblePagesAndCommitOnlyLatestDestination() async throws {
        for layoutDirection in [LayoutDirection.leftToRight, .rightToLeft] {
            let spaces = nativeSpaces(count: 8)
            let (window, viewport) = makeNativeViewport()
            defer {
                viewport.teardown()
                window.contentView = nil
                window.close()
            }
            var selections: [SpaceID] = []
            viewport.update(
                spaces: spaces, selectedSpaceID: spaces[0].id, isInteractionLocked: false,
                reduceMotion: false, layoutDirection: layoutDirection,
                selectSpace: {
                    selections.append($0)
                    return $0
                }, settledSpace: { _ in },
                makeRoot: nativeRoot)
            viewport.layoutSubtreeIfNeeded()
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(20))
            let forward: CGFloat = layoutDirection == .leftToRight ? -1 : 1

            // Restart several short flicks before any transition has settled or
            // presented another frame. Pending destinations must not outrun
            // the actual pages and leave the viewport empty.
            for _ in 0..<6 {
                let token = try XCTUnwrap(viewport.beginInteractiveMotion())
                XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: forward * 16, token: token))
                let visibleWidth = viewport.subviews.filter { !$0.isHidden }.reduce(CGFloat.zero) {
                    let intersection = $1.frame.intersection(viewport.bounds)
                    return $0 + (intersection.isNull ? 0 : intersection.width)
                }
                XCTAssertEqual(visibleWidth, viewport.bounds.width, accuracy: 0.5)
                XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 1800, cancelled: false, token: token))
                XCTAssertTrue(selections.isEmpty)
            }
            try await awaitSettlement(viewport)
            XCTAssertEqual(selections, [spaces[1].id])

            // A short fresh flick qualifies independently of the unfinished
            // incoming offset. It must advance now, without a third gesture.
            let firstFlick = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: forward * 224, token: firstFlick))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 500, cancelled: false, token: firstFlick))
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(20))
            let nextFlick = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertEqual(viewport.presentationSpaceID, spaces[2].id)
            let incoming = try XCTUnwrap(
                viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                    $0.hostingView.rootView.assignment.spaceID == spaces[2].id
                })
            let inherited = incoming.frame.minX
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: forward * 32, token: nextFlick))
            XCTAssertEqual(incoming.frame.minX, inherited + forward * 32, accuracy: 0.001)
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 1000, cancelled: false, token: nextFlick))
            try await assertDirectSettlement(
                viewport, host: incoming, start: inherited + forward * 32, endpoint: forward * viewport.bounds.width)
            XCTAssertEqual(selections, [spaces[1].id, spaces[3].id])

            // Return to the previous baseline for reversal and slow-drag cases.
            viewport.update(
                spaces: spaces, selectedSpaceID: spaces[1].id, isInteractionLocked: false,
                reduceMotion: false, layoutDirection: layoutDirection,
                selectSpace: {
                    selections.append($0)
                    return $0
                }, settledSpace: { _ in }, makeRoot: nativeRoot)
            selections = [spaces[1].id]

            // A later reversal takes over the partially arrived next page;
            // its superseded completion must never select that next Space.
            let outgoing = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: forward * 224, token: outgoing))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 500, cancelled: false, token: outgoing))
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(20))
            let reverse = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertEqual(viewport.presentationSpaceID, spaces[2].id)
            XCTAssertFalse(viewport.endInteractiveMotion(velocity: 0, cancelled: false, token: outgoing))
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -forward * 32, token: reverse))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: -forward * 1400, cancelled: false, token: reverse))
            try await awaitSettlement(viewport)
            XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
            XCTAssertEqual(selections, [spaces[1].id])

            // A slow continuation still counts the distance already visible
            // before interruption when choosing which page to settle on.
            let partial = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: forward * 120, token: partial))
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 1000, cancelled: false, token: partial))
            let continuation = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: forward * 60, token: continuation))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: false, token: continuation))
            try await awaitSettlement(viewport)
            XCTAssertEqual(selections, [spaces[1].id, spaces[2].id])

            // Even a fast release close to the endpoint must never pass it.
            let fast = try XCTUnwrap(viewport.beginInteractiveMotion())
            let outgoingHost = try XCTUnwrap(
                viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                    $0.hostingView.rootView.assignment.spaceID == spaces[2].id
                })
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: forward * 300, token: fast))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 4000, cancelled: false, token: fast))
            try await assertDirectSettlement(
                viewport, host: outgoingHost, start: forward * 300, endpoint: forward * viewport.bounds.width)
            XCTAssertEqual(viewport.presentationSpaceID, spaces[3].id)
        }
    }

    private func assertDirectSettlement(
        _ viewport: SpacePagerViewport<Text>, host: NSView, start startPosition: CGFloat, endpoint: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        var remaining = abs(endpoint - startPosition)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while viewport.motion != nil, ContinuousClock.now < deadline {
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(10))
            let position = host.layer?.presentation()?.frame.minX ?? host.frame.minX
            XCTAssertGreaterThanOrEqual(position, min(startPosition, endpoint) - 0.5, file: file, line: line)
            XCTAssertLessThanOrEqual(position, max(startPosition, endpoint) + 0.5, file: file, line: line)
            let nextRemaining = abs(endpoint - position)
            XCTAssertLessThanOrEqual(
                nextRemaining, remaining + 0.5, "Settling must not reverse direction", file: file, line: line)
            remaining = nextRemaining
        }
        XCTAssertNil(viewport.motion, file: file, line: line)
        XCTAssertEqual(host.frame.minX, endpoint, accuracy: 0.5, file: file, line: line)
    }

    private func awaitSettlement(_ viewport: SpacePagerViewport<Text>) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while viewport.motion != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(viewport.motion, "The native animation must deliver its completion")
    }

    private func assertPageFrames(
        _ viewport: SpacePagerViewport<Text>, spaces: [BrowserSpace], selectedIndex: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for host in viewport.subviews.compactMap({ $0 as? SpacePageHost<Text> }) {
            guard let index = spaces.firstIndex(where: { $0.id == host.hostingView.rootView.assignment.spaceID })
            else { continue }
            let expectedX = CGFloat(index - selectedIndex) * viewport.bounds.width
            XCTAssertEqual(host.frame.minX, expectedX, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(host.frame.size, viewport.bounds.size, file: file, line: line)
            XCTAssertEqual(host.layer?.affineTransform(), .identity, file: file, line: line)
            if let visible = host.layer?.presentation() {
                XCTAssertEqual(visible.frame.minX, expectedX, accuracy: 0.5, file: file, line: line)
            }
        }
    }

    private func makeNativeViewport() -> (NSWindow, SpacePagerViewport<Text>) {
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = SpacePagerViewport<Text>(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.contentView = viewport
        window.orderFront(nil)
        return (window, viewport)
    }

    private func nativeSpaces(count: Int = 3) -> [BrowserSpace] {
        (0..<count).map { index in
            BrowserSpace(
                id: SpaceID(), profile: BrowsingProfile(), name: "Space \(index)",
                symbol: "globe", accent: .indigo, folders: [], tabs: [], selectedTabID: nil)
        }
    }

    private func nativeRoot(_ space: BrowserSpace, _ isSelected: Bool) -> SpacePageRoot<Text> {
        SpacePageRoot(
            content: Text(space.name), environment: EnvironmentValues(),
            assignment: BrowserSpaceRuntimeAssignment(space: space))
    }

    private func input(
        _ x: CGFloat, y: CGFloat = 0, at timestamp: TimeInterval,
        phase: SpaceScrollGesturePolicy.Phase = .none, precise: Bool = true, momentum: Bool = false
    ) -> SpaceScrollGesturePolicy.Input {
        .init(deltaX: x, deltaY: y, timestamp: timestamp, isPrecise: precise, phase: phase, isMomentum: momentum)
    }
}
