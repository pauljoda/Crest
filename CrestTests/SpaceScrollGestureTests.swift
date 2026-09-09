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
        var actualSelection = spaces[0].id
        var acceptsSelection = true
        let (window, viewport) = makeNativeViewport()
        let presentation = SpacePagerPresentation()
        let iconObserver = NSObject()
        let backdropObserver = NSObject()
        var iconSnapshot: SpacePagerPresentation.Snapshot?
        var backdropSnapshot: SpacePagerPresentation.Snapshot?
        presentation.observe(owner: iconObserver) { iconSnapshot = $0 }
        presentation.observe(owner: backdropObserver) { backdropSnapshot = $0 }
        let foreground = SpaceForegroundPresentation()
        foreground.connect(
            presentation,
            tones: spaces.enumerated().map { .init(id: $0.element.id, white: $0.offset == 0 ? 0 : 1) },
            selectedSpaceID: spaces[0].id)

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
                },
                makeRoot: nativeRoot)
        }
        // Keep a previously visited distant page cached alongside the two
        // pages participating in this gesture.
        update(selected: spaces[2].id)
        update(selected: spaces[0].id)
        viewport.layoutSubtreeIfNeeded()
        assertPageFrames(viewport, spaces: spaces, selectedIndex: 0)
        let source = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[0].id
            })
        let distant = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        let distantFrame = distant.frame
        let token = try XCTUnwrap(viewport.beginInteractiveMotion())
        var distance: CGFloat = 0
        for delta in [CGFloat(-3), -17, -90, 12] {
            distance += delta
            XCTAssertTrue(track(viewport, deltaX: delta, token: token))
            XCTAssertEqual(source.frame.minX, distance, accuracy: 0.001)
            XCTAssertEqual(distant.frame, distantFrame, "Offscreen layouts must stay stationary during tracking")
            XCTAssertFalse(distant.isHidden, "Cached layouts must stay attached through focus and page handoffs")
            XCTAssertEqual(
                try XCTUnwrap(presentation.snapshot).position, -distance / viewport.bounds.width,
                accuracy: 0.000_001)
            XCTAssertEqual(presentation.snapshot?.phase, .tracking)
            XCTAssertEqual(iconSnapshot, presentation.snapshot)
            XCTAssertEqual(backdropSnapshot, presentation.snapshot)
            XCTAssertEqual(
                Double(try XCTUnwrap(foreground.position)), Double(-distance / viewport.bounds.width),
                accuracy: 0.000_001)

        }
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertTrue(selections.isEmpty)

        // A short, fast flick can finish a page without first dragging halfway.
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -1200, cancelled: false, token: token))
        XCTAssertEqual(distant.frame, distantFrame, "Settling must not animate an offscreen layout")
        XCTAssertFalse(distant.isHidden, "Settling must not discard a retained layout")
        XCTAssertTrue(distant.layer?.animationKeys()?.isEmpty ?? true)
        XCTAssertTrue(selections.isEmpty, "Finger release must not interrupt the settling frames")
        XCTAssertEqual(presentation.snapshot?.phase, .settling)
        XCTAssertEqual(
            try XCTUnwrap(presentation.snapshot).position, -distance / viewport.bounds.width,
            accuracy: 0.000_001)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id])
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 1)
        XCTAssertEqual(foreground.position, 1)
        XCTAssertEqual(iconSnapshot, presentation.snapshot)
        XCTAssertEqual(backdropSnapshot, presentation.snapshot)
        presentation.removeObserver(owner: backdropObserver)
        let lastBackdropSnapshot = backdropSnapshot
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -1200, cancelled: false, token: token))
        XCTAssertEqual(selections, [spaces[1].id])

        // The native selection receipt can precede SwiftUI reconciliation.
        // Returning immediately must still undo the accepted B selection.
        let returning = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 224, token: returning))
        XCTAssertEqual(iconSnapshot, presentation.snapshot)
        XCTAssertEqual(backdropSnapshot, lastBackdropSnapshot, "Removing a background must leave the icon connected")
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 500, cancelled: false, token: returning))
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id, spaces[0].id])
        XCTAssertEqual(actualSelection, spaces[0].id)
        XCTAssertEqual(foreground.position, 0)
        foreground.disconnect()
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
        XCTAssertTrue(track(viewport, deltaX: 64, token: cancelled))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 1000, cancelled: true, token: cancelled))
        XCTAssertNotNil(viewport.motion, "Cancellation must settle back instead of snapping at finger release")
        try await awaitSettlement(viewport)
        XCTAssertEqual(
            selections, [spaces[1].id, spaces[0].id, spaces[1].id],
            "Cancellation must not select a different Space")

        acceptsSelection = false
        let refused = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: -240, token: refused))
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
                },
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
        XCTAssertTrue(track(viewport, deltaX: -224, token: first))
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
        XCTAssertTrue(track(viewport, deltaX: -1, token: second))
        XCTAssertEqual(source.frame.minX, inherited - 1, accuracy: 0.001)
        viewport.layoutSubtreeIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            (sourceLayer.presentation() ?? sourceLayer).frame.minX, inherited - 1, accuracy: 0.5,
            "An interrupted animation must stay stopped after AppKit layout and the next frame")
        XCTAssertTrue(track(viewport, deltaX: -255, token: second))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -900, cancelled: false, token: second))
        XCTAssertTrue(selections.isEmpty)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[2].id])
        update(selected: spaces[2].id)

        let superseded = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 128, token: superseded))
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
        XCTAssertTrue(track(viewport, deltaX: 39, token: edge))
        XCTAssertEqual(source.frame.minX, 0, "The first Space must not expose empty space beyond its edge")
        XCTAssertTrue(track(viewport, deltaX: 1, token: edge))
        XCTAssertEqual(source.frame.minX, 0)
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 1000, cancelled: false, token: edge))
        XCTAssertNil(viewport.motion, "An unmoved page has no return animation")
        let edgeRestart = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 100, token: edgeRestart))
        XCTAssertEqual(source.frame.minX, 0)
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: true, token: edgeRestart))
        XCTAssertNil(viewport.motion)
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
        XCTAssertTrue(track(viewport, deltaX: -32, token: protected))
        spaces[1].accessPolicy = .deviceOwnerAuthentication
        update(selected: spaces[0].id)
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: protected))

        update(selected: spaces[2].id)
        let detached = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 64, token: detached))
        window.contentView = nil
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 2)
        window.contentView = viewport
        let tornDown = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 64, token: tornDown))
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
                },
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
                XCTAssertTrue(track(viewport, deltaX: forward * 16, token: token))
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
            XCTAssertTrue(track(viewport, deltaX: forward * 224, token: firstFlick))
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
            XCTAssertTrue(track(viewport, deltaX: forward * 32, token: nextFlick))
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
                }, makeRoot: nativeRoot)
            selections = [spaces[1].id]

            // A later reversal takes over the partially arrived next page;
            // its superseded completion must never select that next Space.
            let outgoing = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertTrue(track(viewport, deltaX: forward * 224, token: outgoing))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 500, cancelled: false, token: outgoing))
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(20))
            let reverse = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertEqual(viewport.presentationSpaceID, spaces[2].id)
            XCTAssertFalse(viewport.endInteractiveMotion(velocity: 0, cancelled: false, token: outgoing))
            XCTAssertTrue(track(viewport, deltaX: -forward * 32, token: reverse))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: -forward * 1400, cancelled: false, token: reverse))
            try await awaitSettlement(viewport)
            XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
            XCTAssertEqual(selections, [spaces[1].id])

            // A slow continuation still counts the distance already visible
            // before interruption when choosing which page to settle on.
            let partial = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertTrue(track(viewport, deltaX: forward * 120, token: partial))
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 1000, cancelled: false, token: partial))
            let continuation = try XCTUnwrap(viewport.beginInteractiveMotion())
            XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
            XCTAssertTrue(track(viewport, deltaX: forward * 60, token: continuation))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: false, token: continuation))
            try await awaitSettlement(viewport)
            XCTAssertEqual(selections, [spaces[1].id, spaces[2].id])

            // Even a fast release close to the endpoint must never pass it.
            let fast = try XCTUnwrap(viewport.beginInteractiveMotion())
            let outgoingHost = try XCTUnwrap(
                viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                    $0.hostingView.rootView.assignment.spaceID == spaces[2].id
                })
            XCTAssertTrue(track(viewport, deltaX: forward * 300, token: fast))
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: forward * 4000, cancelled: false, token: fast))
            try await assertDirectSettlement(
                viewport, host: outgoingHost, start: forward * 300, endpoint: forward * viewport.bounds.width)
            XCTAssertEqual(viewport.presentationSpaceID, spaces[3].id)

            // Long gestures stop at the next page, and excess input must not
            // accumulate into a dead zone when the fingers reverse direction.
            let long = try XCTUnwrap(viewport.beginInteractiveMotion())
            let longSource = try XCTUnwrap(
                viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                    $0.hostingView.rootView.assignment.spaceID == spaces[3].id
                })
            let endpoint = forward * viewport.bounds.width
            XCTAssertTrue(track(viewport, deltaX: forward * 480, token: long))
            XCTAssertEqual(longSource.frame.minX, endpoint, accuracy: 0.001)
            XCTAssertTrue(track(viewport, deltaX: forward * 80, token: long))
            XCTAssertEqual(longSource.frame.minX, endpoint, accuracy: 0.001)
            XCTAssertTrue(track(viewport, deltaX: -forward, token: long))
            XCTAssertEqual(longSource.frame.minX, endpoint - forward, accuracy: 0.001)
            XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: false, token: long))
            try await assertDirectSettlement(viewport, host: longSource, start: endpoint - forward, endpoint: endpoint)
            XCTAssertEqual(viewport.presentationSpaceID, spaces[4].id)
        }
    }

    func testFastInputBurstsRemainVisibleAndSettleAtABoundedSpeed() async throws {
        let spaces = nativeSpaces()
        let (window, viewport) = makeNativeViewport()
        defer {
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        var selections: [SpaceID] = []
        viewport.update(
            spaces: spaces, selectedSpaceID: spaces[0].id, isInteractionLocked: false,
            reduceMotion: false, layoutDirection: .leftToRight,
            selectSpace: {
                selections.append($0)
                return $0
            },
            makeRoot: nativeRoot)
        viewport.layoutSubtreeIfNeeded()
        let source = try XCTUnwrap(viewport.subviews.first { $0.frame.minX == 0 })
        let token = try XCTUnwrap(viewport.beginInteractiveMotion())
        for _ in 0..<20 {
            XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -80, token: token))
        }
        XCTAssertEqual(source.frame.minX, 0, "Input in one run-loop turn must coalesce into a display frame")
        // Offscreen windows do not receive NSView display-link callbacks;
        // advance the same frame consumer at a controlled display cadence.
        viewport.advanceFrame(interval: 1.0 / 120)
        let first = source.frame.minX
        XCTAssertLessThan(first, 0, "Tracking must start on the first display frame without a gesture threshold")
        XCTAssertGreaterThanOrEqual(first, -viewport.bounds.width * 4 / 120)
        viewport.advanceFrame(interval: 1)
        XCTAssertLessThanOrEqual(
            first - source.frame.minX, viewport.bounds.width * 4 / 60 + 0.001,
            "A delayed frame must not jump across the accumulated travel")
        let beforeReverse = source.frame.minX
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: 1, token: token))
        viewport.advanceFrame(interval: 1.0 / 60)
        XCTAssertEqual(
            source.frame.minX, beforeReverse + 1, accuracy: 0.001,
            "Reversing must discard pending forward travel")
        XCTAssertTrue(viewport.updateInteractiveMotion(deltaX: -1600, token: token))
        let visible = source.frame.minX
        XCTAssertGreaterThan(visible, -viewport.bounds.width / 2, "A burst must not jump straight to its target")
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -12000, cancelled: false, token: token))
        CATransaction.flush()
        viewport.advanceFrame(interval: 1.0 / 120)
        XCTAssertTrue(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.contains {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            },
            "The next forward neighbor must be ready before the current slide finishes")
        XCTAssertLessThanOrEqual(viewport.subviews.count, 4)
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertNotNil(viewport.motion, "Release velocity must not compress a large slide into 100 ms")
        XCTAssertTrue(selections.isEmpty)
        let presented = try XCTUnwrap(source.layer?.presentation()).frame.minX
        let progress = (presented - visible) / (-viewport.bounds.width - visible)
        XCTAssertGreaterThan(
            progress, 0.75, "The measured reference covers most remaining travel early, then eases into place")
        try await assertDirectSettlement(
            viewport, host: source, start: visible, endpoint: -viewport.bounds.width)
        XCTAssertEqual(selections, [spaces[1].id])
    }

    func testHostedPagesInheritEnvironmentChangesThroughNativeHierarchy() async throws {
        let spaces = nativeSpaces(count: 2)
        var appearances: [SpaceID: ColorScheme] = [:]
        var presentations: [SpaceID: ObjectIdentifier] = [:]
        let first = SpacePagerPresentation()
        let second = SpacePagerPresentation()
        let pager = PlatformSpacePager(
            spaces: spaces, selectedSpaceID: spaces[0].id, isInteractionLocked: false,
            selectSpace: { $0 },
            content: { space, _ in
                HostedPageEnvironmentReader { appearance, presentation in
                    appearances[space.id] = appearance
                    presentations[space.id] = presentation.map(ObjectIdentifier.init)
                }
            })
        let root = NSHostingView(
            rootView: pager.environment(\.colorScheme, .dark).environment(\.spacePagerPresentation, first))
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        for (appearance, presentation) in [(ColorScheme.dark, first), (.light, second)] {
            root.rootView = pager.environment(\.colorScheme, appearance)
                .environment(\.spacePagerPresentation, presentation)
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while ContinuousClock.now < deadline {
                root.layoutSubtreeIfNeeded()
                if spaces.allSatisfy({
                    appearances[$0.id] == appearance && presentations[$0.id] == ObjectIdentifier(presentation)
                }) {
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            for space in spaces {
                XCTAssertEqual(appearances[space.id], appearance)
                XCTAssertEqual(presentations[space.id], ObjectIdentifier(presentation))
            }
        }
    }

    func testSpaceDecorationsKeepPaceWithNativeSettlementWithoutProgressCallbacks() async throws {
        let spaces = nativeSpaces(count: 6)
        let (window, viewport) = makeNativeViewport()
        let presentation = SpacePagerPresentation()
        let insets = Dictionary(
            uniqueKeysWithValues: spaces.enumerated().map { ($0.element.id, $0.offset == 3 ? CGFloat(48) : 9) })
        let toolbar = SpaceSidebarToolbarView(frame: CGRect(x: 0, y: 100, width: 320, height: 48))
        let pool = BrowserExtensionControllerPool(
            registry: BrowserExtensionRegistry(persistence: InMemoryBrowserExtensionRegistryPersistence()))
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.contentView = container
        container.addSubview(viewport)
        container.addSubview(toolbar)
        viewport.frame.origin.y = 100
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 120, height: 32))
        let picker = SpacePickerPresentationView(frame: CGRect(x: 0, y: 0, width: 246, height: 32))
        scroll.documentView = picker
        container.addSubview(scroll)
        let backdrop = SpaceBackdropBlendView<Color>(frame: CGRect(x: 0, y: 40, width: 320, height: 50))
        container.addSubview(backdrop)
        let cards = SpaceContentPagerView<Text>(frame: CGRect(x: 0, y: 40, width: 960, height: 50))
        container.addSubview(cards)
        defer {
            toolbar.disconnect()
            picker.disconnect()
            backdrop.disconnect()
            cards.disconnect()
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        viewport.update(
            spaces: spaces, selectedSpaceID: spaces[2].id, isInteractionLocked: false,
            reduceMotion: false, layoutDirection: .leftToRight, presentation: presentation, contentTopInsets: insets,
            selectSpace: { $0 }, makeRoot: nativeRoot)
        toolbar.update(
            spaces: spaces, selectedSpaceID: spaces[2].id, toolbarSpaces: [spaces[3].id], contentTopInsets: insets,
            presentation: presentation
        ) { space in
            SpaceSidebarToolbarRoot(
                space: space, pool: pool, isLocked: false,
                actions: space.id == spaces[3].id ? [.init(id: "probe", displayName: "Extension", isPinned: true)] : [])
        }
        picker.update(
            presentation: presentation, spaces: spaces, selectedSpaceID: spaces[2].id,
            frames: Dictionary(
                uniqueKeysWithValues: spaces.enumerated().map {
                    ($0.element.id, CGRect(x: CGFloat($0.offset) * 41, y: 0, width: 40, height: 30))
                }), selectionTint: .blue)
        backdrop.update(spaces: spaces, selectedSpace: spaces[2], presentation: presentation) { space in
            SpaceBackdropRoot(background: space?.id == spaces[3].id ? Color.white : Color.black)
        }
        cards.update(
            spaces: spaces, selectedSpaceID: spaces[2].id, lockedSpaceIDs: [], layoutDirection: .leftToRight,
            presentation: presentation, makeRoot: nativeRoot)
        container.layoutSubtreeIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(30))
        let source = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        let highlight = try XCTUnwrap(picker.layer?.sublayers?.first as? CAShapeLayer)
        let token = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: -120, token: token))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -1200, cancelled: false, token: token))
        CATransaction.flush()
        // Deliberately deny main-thread progress callbacks. Native page motion
        // already continues in the compositor; its decoration must do so too.
        usleep(90_000)
        let position = 2 - (try XCTUnwrap(source.layer?.presentation()).frame.minX / viewport.bounds.width)
        XCTAssertGreaterThan(position, 2.5)
        let incomingToolbar = try XCTUnwrap(
            toolbar.subviews.compactMap { $0 as? SpacePageHost<SpaceSidebarToolbarRoot> }
                .first { $0.hostingView.rootView.content.space.id == spaces[3].id })
        XCTAssertEqual(
            try XCTUnwrap(source.layer?.presentation()).frame.minY, 9 + 39 * (position - 2), accuracy: 1.3,
            "The tab list's vertical shift must share horizontal presentation progress")
        XCTAssertEqual(
            try XCTUnwrap(incomingToolbar.layer?.presentation()).frame.maxY,
            try XCTUnwrap(source.layer?.presentation()).frame.minY, accuracy: 1.3,
            "Extension controls must stay above the pinned tiles throughout the swipe")
        XCTAssertEqual(
            CGFloat(try XCTUnwrap(incomingToolbar.layer?.presentation()).opacity), position - 2, accuracy: 0.03,
            "Toolbar icons must keep fading while the main thread is busy")
        let sourceCard = try XCTUnwrap(
            cards.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        XCTAssertEqual(
            2 - (try XCTUnwrap(sourceCard.layer?.presentation()).frame.minX / cards.bounds.width), position,
            accuracy: 0.03, "Full-width cards must follow sidebar progress, independent of their width")
        XCTAssertEqual(
            try XCTUnwrap(highlight.presentation()).frame.minX / 41, position, accuracy: 0.03,
            "The selection highlight must keep moving with the page during main-thread work")
        XCTAssertEqual(
            try XCTUnwrap(scroll.contentView.layer?.presentation()).bounds.minX,
            position * 41 + 20 - 60, accuracy: 1.3,
            "The icon lane must use the page's settling clock")
        let overlay = try XCTUnwrap(
            backdrop.subviews.compactMap {
                $0 as? NSHostingView<SpaceBackdropRoot<Color>>
            }.first { $0.rootView.background == Color.white })
        XCTAssertEqual(
            CGFloat(try XCTUnwrap(overlay.layer?.presentation()).opacity), position - 2, accuracy: 0.03,
            "The background blend must use the same presentation progress")
        // Interrupt while the incoming Space is still between neighbors, then
        // flick onward across its boundary. No leaf may retain the old clock.
        let continuing = try XCTUnwrap(viewport.beginInteractiveMotion())
        let inherited = try XCTUnwrap(presentation.snapshot).position
        XCTAssertEqual(highlight.frame.minX / 41, inherited, accuracy: 0.001)
        XCTAssertTrue(track(viewport, deltaX: -4, token: continuing))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -2000, cancelled: false, token: continuing))
        CATransaction.flush()
        usleep(90_000)
        let continuedPosition = 2 - (try XCTUnwrap(source.layer?.presentation()).frame.minX / viewport.bounds.width)
        XCTAssertGreaterThan(continuedPosition, 3)
        XCTAssertEqual(
            try XCTUnwrap(source.layer?.presentation()).frame.minY, 48 - 39 * (continuedPosition - 3), accuracy: 1.3)
        XCTAssertEqual(
            CGFloat(try XCTUnwrap(incomingToolbar.layer?.presentation()).opacity), 4 - continuedPosition, accuracy: 0.03
        )
        XCTAssertLessThanOrEqual(toolbar.subviews.count, 4)
        XCTAssertEqual(
            2 - (try XCTUnwrap(sourceCard.layer?.presentation()).frame.minX / cards.bounds.width), continuedPosition,
            accuracy: 0.03, "A continuation must replace the card timeline along with the sidebar timeline")
        XCTAssertEqual(
            try XCTUnwrap(highlight.presentation()).frame.minX / 41, continuedPosition, accuracy: 0.03)
        XCTAssertEqual(
            try XCTUnwrap(scroll.contentView.layer?.presentation()).bounds.minX,
            continuedPosition * 41 + 20 - 60, accuracy: 1.3)
        let finalBackground = try XCTUnwrap(backdrop.subviews.first { $0.layer?.zPosition == 4 })
        XCTAssertEqual(
            CGFloat(try XCTUnwrap(finalBackground.layer?.presentation()).opacity), continuedPosition - 3,
            accuracy: 0.03)
        var loadedInsets = insets
        loadedInsets[spaces[4].id] = 48
        viewport.update(
            spaces: spaces, selectedSpaceID: spaces[2].id, isInteractionLocked: false,
            reduceMotion: false, layoutDirection: .leftToRight, presentation: presentation,
            contentTopInsets: loadedInsets, selectSpace: { $0 }, makeRoot: nativeRoot)
        XCTAssertEqual(
            source.frame.minY, 9, accuracy: 0.01,
            "An extension finishing startup must not change the swipe's destination geometry")
        try await awaitSettlement(viewport)
        XCTAssertEqual(
            source.frame.minY, 48, accuracy: 0.01,
            "The deferred toolbar inset must be applied after the swipe settles")
        XCTAssertEqual(presentation.snapshot?.position, 4)
        XCTAssertNil(presentation.snapshot?.transition)
        XCTAssertTrue(highlight.animationKeys()?.isEmpty ?? true)
        let unlockedHost = try XCTUnwrap(
            cards.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[4].id
            })
        cards.update(
            spaces: spaces, selectedSpaceID: spaces[4].id, lockedSpaceIDs: [spaces[4].id],
            layoutDirection: .leftToRight, presentation: presentation, makeRoot: nativeRoot)
        XCTAssertNil(unlockedHost.superview, "Relocking must immediately withdraw the previously clear host")
        XCTAssertLessThanOrEqual(cards.subviews.count, 4, "Content retention must stay bounded")
        // With page motion disabled, the same retained surface stays still
        // through sidebar tracking and changes only when selection commits.
        cards.update(
            spaces: spaces, selectedSpaceID: spaces[4].id, lockedSpaceIDs: [spaces[4].id],
            layoutDirection: .leftToRight, presentation: nil, makeRoot: nativeRoot)
        let stationary = try XCTUnwrap(
            cards.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[4].id
            })
        presentation.publish(
            .init(
                generation: 100, spaceIDs: spaces.map(\.id), position: 4.5,
                phase: .tracking, destinationID: spaces[5].id))
        XCTAssertEqual(stationary.frame.minX, 0, accuracy: 0.001)
        cards.update(
            spaces: spaces, selectedSpaceID: spaces[5].id, lockedSpaceIDs: [spaces[4].id],
            layoutDirection: .leftToRight, presentation: nil, makeRoot: nativeRoot)
        let destination = try XCTUnwrap(
            cards.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[5].id
            })
        XCTAssertEqual(destination.frame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(stationary.frame.minX, -cards.bounds.width, accuracy: 0.001)

    }

    // Geometry/lifecycle cases deliver enough display frames for the given
    // drag to arrive. The burst case separately tests coalescing and speed.
    private func track(_ viewport: SpacePagerViewport<Text>, deltaX: CGFloat, token: UInt) -> Bool {
        guard viewport.updateInteractiveMotion(deltaX: deltaX, token: token) else { return false }
        for _ in 0..<60 { viewport.advanceFrame(interval: 1.0 / 60) }
        return true
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
            content: Text(space.name),
            assignment: BrowserSpaceRuntimeAssignment(space: space))
    }

    private func input(
        _ x: CGFloat, y: CGFloat = 0, at timestamp: TimeInterval,
        phase: SpaceScrollGesturePolicy.Phase = .none, precise: Bool = true, momentum: Bool = false
    ) -> SpaceScrollGesturePolicy.Input {
        .init(deltaX: x, deltaY: y, timestamp: timestamp, isPrecise: precise, phase: phase, isMomentum: momentum)
    }
}

private struct HostedPageEnvironmentReader: View {
    @Environment(\.colorScheme) private var appearance
    @Environment(\.spacePagerPresentation) private var presentation
    let report: (ColorScheme, SpacePagerPresentation?) -> Void

    var body: some View {
        Color.clear
            .onAppear { report(appearance, presentation) }
            .onChange(of: appearance) { _, _ in report(appearance, presentation) }
            .onChange(of: presentation.map(ObjectIdentifier.init)) { _, _ in report(appearance, presentation) }
    }
}
