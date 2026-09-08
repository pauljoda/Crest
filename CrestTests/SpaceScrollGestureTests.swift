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

    func testNativePagingMovesBeforeCommittingAndIgnoresCompletedCallbacks() throws {
        let spaces = nativeSpaces()
        var selections: [SpaceID] = []
        var settlements: [SpaceID] = []
        var actualSelection = spaces[0].id
        var acceptsSelection = true
        let (window, viewport) = makeNativeViewport()
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
                selectSpace: {
                    selections.append($0)
                    if acceptsSelection { actualSelection = $0 }
                    return actualSelection
                }, settledSpace: { settlements.append($0) },
                makeRoot: nativeRoot)
        }
        update(selected: spaces[0].id)
        let source = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[0].id
            })
        let token = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(-0.3, phase: .changed, token: token, complete: false))
        XCTAssertEqual(try XCTUnwrap(source.layer).affineTransform().tx, -0.3 * viewport.bounds.width, accuracy: 0.001)
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertTrue(settlements.isEmpty)

        XCTAssertTrue(viewport.updateInteractiveMotion(-0.6, phase: .ended, token: token, complete: false))
        XCTAssertTrue(selections.isEmpty, "Physical completion must not interrupt the native settling frames")
        XCTAssertTrue(viewport.updateInteractiveMotion(-1, phase: [], token: token, complete: true))
        XCTAssertEqual(selections, [spaces[1].id])
        XCTAssertEqual(settlements, [spaces[1].id])
        update(selected: spaces[1].id)
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertFalse(viewport.updateInteractiveMotion(-1, phase: [], token: token, complete: true))
        XCTAssertEqual(selections, [spaces[1].id])
        XCTAssertEqual(settlements, [spaces[1].id])

        let cancelled = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(0.2, phase: .changed, token: cancelled, complete: false))
        XCTAssertTrue(viewport.updateInteractiveMotion(0, phase: .cancelled, token: cancelled, complete: true))
        XCTAssertEqual(selections, [spaces[1].id], "Returning to the origin must not select a different Space")

        acceptsSelection = false
        let refused = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(-1, phase: .ended, token: refused, complete: true))
        XCTAssertEqual(selections, [spaces[1].id, spaces[2].id])
        XCTAssertEqual(viewport.selectedSpaceID, spaces[1].id)
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertNotNil(viewport.beginInteractiveMotion(), "A refused selection must not leave the viewport locked")
    }

    func testNativePagingRebasesInterruptedSuccessAndRejectsInvalidatedGestures() throws {
        let spaces = nativeSpaces()
        var selections: [SpaceID] = []
        let (window, viewport) = makeNativeViewport()
        defer {
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        func update(selected: SpaceID, locked: Bool = false) {
            viewport.update(
                spaces: spaces, selectedSpaceID: selected, isInteractionLocked: locked,
                reduceMotion: false, layoutDirection: .leftToRight,
                selectSpace: {
                    selections.append($0)
                    return $0
                }, settledSpace: { _ in }, makeRoot: nativeRoot)
        }
        update(selected: spaces[0].id)
        let first = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(-0.7, phase: .ended, token: first, complete: false))
        viewport.interruptForNewGesture()
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertTrue(selections.isEmpty)

        let second = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertFalse(viewport.updateInteractiveMotion(-1, phase: [], token: first, complete: true))
        XCTAssertTrue(viewport.updateInteractiveMotion(-0.8, phase: .ended, token: second, complete: false))
        XCTAssertTrue(selections.isEmpty)
        XCTAssertTrue(viewport.updateInteractiveMotion(-1, phase: [], token: second, complete: true))
        XCTAssertEqual(selections, [spaces[2].id])
        update(selected: spaces[2].id)

        let superseded = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(viewport.updateInteractiveMotion(0.4, phase: .changed, token: superseded, complete: false))
        update(selected: spaces[0].id)
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertFalse(viewport.updateInteractiveMotion(1, phase: .ended, token: superseded, complete: true))
        update(selected: spaces[0].id, locked: true)
        XCTAssertNil(viewport.beginInteractiveMotion())
        XCTAssertEqual(viewport.presentationSpaceID, spaces[0].id)
        XCTAssertEqual(selections, [spaces[2].id])
    }

    private func makeNativeViewport() -> (NSWindow, SpacePagerViewport<Text>) {
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = SpacePagerViewport<Text>(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.contentView = viewport
        return (window, viewport)
    }

    private func nativeSpaces() -> [BrowserSpace] {
        (0..<3).map { index in
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
