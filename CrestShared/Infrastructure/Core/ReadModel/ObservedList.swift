import Foundation
import Observation

/// An ordered list of read-model objects, one per record identity. A change
/// updates the object that holds a record in place, so only the observers of
/// the fields that changed hear of it. `models` is reassigned only when the
/// list's membership or order changes, which is all a list's own observers
/// read.
@MainActor
@Observable
final class ObservedList<Model: ObservedModel & Identifiable>
where Model.ID == UUID, Model.Value: Identifiable, Model.Value.ID == UUID {
    // MARK: - Variables

    /// The objects, in order.
    private(set) var models: [Model] = []
    @ObservationIgnored private var byID: [UUID: Model] = [:]

    /// The records, in order. Reading them observes every field of every object.
    var values: [Model.Value] { models.map(\.value) }

    // MARK: - Initializers

    init(_ values: [Model.Value]) {
        replace(with: values)
    }

    // MARK: - Actions - Reading

    /// The object that holds the record with this identity, or nil when the
    /// list holds none. Reading it observes the list's membership.
    func model(_ id: UUID) -> Model? {
        access(keyPath: \.models)
        return byID[id]
    }

    func contains(_ id: UUID) -> Bool {
        model(id) != nil
    }

    // MARK: - Actions - Changes

    /// Applies one change the way the core's list changes read: the `removed`
    /// records are gone, each `updated` record replaces the one with its
    /// identity where it stands or goes after the others when it is new, and
    /// `order`, when present, names every record in its new order.
    func apply(updated: [Model.Value], removed: [UUID], order: [UUID]?) {
        var next = models
        var isRearranged = false
        if !removed.isEmpty {
            let gone = Set(removed)
            if next.contains(where: { gone.contains($0.id) }) {
                next.removeAll { gone.contains($0.id) }
                isRearranged = true
            }
            for id in removed { byID[id] = nil }
        }
        for value in updated {
            if let model = byID[value.id] {
                model.update(value)
            } else {
                let model = Model(value)
                byID[value.id] = model
                next.append(model)
                isRearranged = true
            }
        }
        if let order {
            let ordered = order.compactMap { byID[$0] }
            if !ordered.elementsEqual(next, by: ===) {
                let kept = Set(order)
                for model in next where !kept.contains(model.id) { byID[model.id] = nil }
                next = ordered
                isRearranged = true
            }
        }
        if isRearranged { models = next }
    }

    /// Takes a whole new list, keeping the object of every record it still holds.
    func replace(with values: [Model.Value]) {
        let kept = Set(values.map(\.id))
        apply(updated: values, removed: models.map(\.id).filter { !kept.contains($0) }, order: values.map(\.id))
    }
}
