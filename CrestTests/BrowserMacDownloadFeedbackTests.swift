import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMacDownloadFeedbackTests: XCTestCase {

    func testFeedbackConsumesOnceAndNeverReplaysAfterContextChange() {
        let state = BrowserMacDownloadFeedbackState()
        let context = makeContext()
        let event = makeEvent(context)
        state.reconcile(events: [], context: context)
        state.reconcile(events: [event], context: context)
        XCTAssertEqual(state.flights.map(\.id), [event.id])
        state.reconcile(events: [event], context: context)
        XCTAssertEqual(state.flights.count, 1)
        var hidden = context
        hidden.isVisible = false
        state.reconcile(events: [event], context: hidden)
        XCTAssertTrue(state.flights.isEmpty)
        state.reconcile(events: [event], context: context)
        XCTAssertTrue(state.flights.isEmpty)
        state.arrive(event.id)
        XCTAssertNil(state.arrivalID)
    }

    func testFeedbackRejectsOtherWindowSpaceAndProfileAndBounds() {
        let state = BrowserMacDownloadFeedbackState()
        let context = makeContext()
        state.reconcile(events: [], context: context)
        var other = context
        other.spaceID = SpaceID(rawValue: UUID())
        var events = [makeEvent(other)]
        other = context
        other.profileID = UUID()
        events.append(makeEvent(other))
        other = context
        other.windowIdentifier = ObjectIdentifier(NSObject())
        events.append(makeEvent(other))
        state.reconcile(events: events, context: context)
        XCTAssertTrue(state.flights.isEmpty)
    }

    func testResizeCancelsArrivalAndRapidDownloadsStayBounded() {
        let state = BrowserMacDownloadFeedbackState()
        var context = makeContext()
        state.reconcile(events: [], context: context)
        let events = (0..<8).map { _ in makeEvent(context) }
        state.reconcile(events: events, context: context)
        XCTAssertEqual(state.flights.count, 3)
        state.arrive(events.last!.id)
        XCTAssertEqual(state.arrivalID, events.last!.id)
        state.arrive(events.last!.id)
        XCTAssertEqual(state.arrivalCount, 1)
        context.destination = CGRect(x: 80, y: 600, width: 28, height: 28)
        state.reconcile(events: events, context: context)
        XCTAssertTrue(state.flights.isEmpty)
        XCTAssertNil(state.arrivalID)
        XCTAssertEqual(state.arrivalCount, 1, "Canceling feedback must not trigger another Archive bounce")
    }

    func testInitialEventsAreNotReplayedAndMissingArchiveUsesStaticFeedback() {
        let state = BrowserMacDownloadFeedbackState()
        var context = makeContext()
        let old = makeEvent(context)
        state.reconcile(events: [old], context: context)
        XCTAssertTrue(state.flights.isEmpty)
        context.destination = nil
        let event = makeEvent(context)
        state.reconcile(events: [old, event], context: context)
        XCTAssertEqual(state.flights.count, 1)
        XCTAssertNil(state.flights.first?.path)
    }

    private func makeContext() -> BrowserMacDownloadFeedbackContext {
        BrowserMacDownloadFeedbackContext(
            windowIdentifier: ObjectIdentifier(self),
            profileID: UUID(),
            spaceID: SpaceID(rawValue: UUID()),
            tabID: nil,
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 800),
            destination: CGRect(x: 100, y: 700, width: 28, height: 28),
            isVisible: true,
            reduceMotion: false
        )
    }

    private func makeEvent(_ context: BrowserMacDownloadFeedbackContext) -> BrowserDownloadFeedbackEvent {
        BrowserDownloadFeedbackEvent(
            id: UUID(), profileID: context.profileID!, spaceID: context.spaceID!,
            filename: "fixture.txt",
            source: BrowserDownloadFeedbackSource(
                pointInGlobal: CGPoint(x: 500, y: 250),
                windowIdentifier: context.windowIdentifier
            )
        )
    }
}
