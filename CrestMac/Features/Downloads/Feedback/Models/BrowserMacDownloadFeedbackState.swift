import Foundation
import Observation

/// A window consumes each start once, including starts it cannot present.
/// Returning to a Space or revealing the sidebar never replays old feedback.
@Observable
@MainActor
final class BrowserMacDownloadFeedbackState {
    struct Flight: Identifiable {
        let id: UUID
        /// Where the download's icon flies, or nil when it has nowhere to
        /// fly and the window posts a notice instead.
        let path: BrowserMacDownloadFlightPath?
    }

    private(set) var flights: [Flight] = []
    private(set) var arrivalID: UUID?
    private(set) var arrivalCount = 0
    @ObservationIgnored private var observedIDs: Set<UUID> = []
    @ObservationIgnored private var previousContext: BrowserMacDownloadFeedbackContext?

    /// Takes the starts among `events` this window presents in `context`,
    /// and answers the ones new since the last call.
    @discardableResult
    func reconcile(
        events: [BrowserDownloadFeedbackEvent],
        context: BrowserMacDownloadFeedbackContext
    ) -> [Flight] {
        let currentIDs = Set(events.map(\.id))
        defer {
            observedIDs = currentIDs
            previousContext = context
        }
        guard previousContext != nil else { return [] }
        if previousContext != context { cancel() }
        if let arrivalID, !currentIDs.contains(arrivalID) { self.arrivalID = nil }
        // The flights are worked out apart and stored only when they differ:
        // every tab switch changes the context, and a write announces the
        // flights to the window even when there are none.
        var next = flights.filter { currentIDs.contains($0.id) }
        defer { if next.map(\.id) != flights.map(\.id) { flights = next } }
        guard context.isVisible, let window = context.windowIdentifier else { return [] }
        let started = events.filter {
            !observedIDs.contains($0.id)
                && $0.source.windowIdentifier == window
                && $0.spaceID == context.spaceID
                && $0.profileID == context.profileID
        }.map { Flight(id: $0.id, path: path(for: $0, context: context)) }
        next = Array((next + started).suffix(BrowserDownloadFeedbackEvent.maximumVisible))
        return started
    }

    func arrive(_ id: UUID) {
        guard arrivalID != id,
            flights.contains(where: { $0.id == id && $0.path != nil })
        else { return }
        arrivalID = id
        arrivalCount += 1
    }

    func cancel() {
        if !flights.isEmpty { flights.removeAll() }
        if arrivalID != nil { arrivalID = nil }
    }

    private func path(
        for event: BrowserDownloadFeedbackEvent,
        context: BrowserMacDownloadFeedbackContext
    ) -> BrowserMacDownloadFlightPath? {
        guard !context.reduceMotion,
            let destination = context.destination,
            !destination.isEmpty,
            context.bounds.contains(destination),
            context.bounds.contains(event.source.pointInGlobal)
        else { return nil }
        return BrowserMacDownloadFlightPath(
            source: event.source.pointInGlobal,
            destination: CGPoint(x: destination.midX, y: destination.midY),
            bounds: context.bounds
        )
    }
}
