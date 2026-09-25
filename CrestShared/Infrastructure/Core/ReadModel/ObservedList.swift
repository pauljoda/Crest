import Foundation
import Observation

/// An ordered list of read-model objects, one per record identity. A change
/// updates the object that holds a record in place, so only the observers of
/// the fields that changed hear of it. The list itself announces two things
/// apart: its membership, when a record joins or leaves, and its order, which
/// `models` reads and which a membership change also changes. Each is stored
/// before it is announced, so a view that renders during the announcement
/// reads the new list; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class ObservedList<Model: ObservedModel & Identifiable>
where Model.ID == UUID, Model.Value: Identifiable, Model.Value.ID == UUID {
    // MARK: - Variables

    /// The objects, in order. Reading them observes the list's order and
    /// membership.
    var models: [Model] {
        access(keyPath: \.models)
        return modelsStorage
    }
    @ObservationIgnored private var modelsStorage: [Model] = []
    /// The objects by identity. Reading them observes the list's membership
    /// only, so a lookup never redraws for a new order.
    private var membership: [UUID: Model] {
        access(keyPath: \.membership)
        return membershipStorage
    }
    @ObservationIgnored private var membershipStorage: [UUID: Model] = [:]

    /// The records, in order. Reading them observes every field of every object.
    var values: [Model.Value] { models.map(\.value) }

    // MARK: - Initializers

    init(_ values: [Model.Value]) {
        replace(with: values)
    }

    // MARK: - Actions - Reading

    /// The object that holds the record with this identity, or nil when the
    /// list holds none. Reading it observes the list's membership, not its
    /// order.
    func model(_ id: UUID) -> Model? {
        membership[id]
    }

    func contains(_ id: UUID) -> Bool {
        model(id) != nil
    }

    // MARK: - Actions - Changes

    /// Applies one change the way the core's list changes read: the `removed`
    /// records are gone, each `updated` record replaces the one with its
    /// identity where it stands or goes after the others when it is new, and
    /// `order`, when present, names every record in its new order. The list
    /// stores its new order and membership before it announces either.
    func apply(updated: [Model.Value], removed: [UUID], order: [UUID]?) {
        var next = modelsStorage
        var byID = membershipStorage
        var isRearranged = false
        var isMembershipChanged = false
        if !removed.isEmpty {
            let gone = Set(removed)
            if next.contains(where: { gone.contains($0.id) }) {
                next.removeAll { gone.contains($0.id) }
                isRearranged = true
            }
            for id in removed where byID.removeValue(forKey: id) != nil { isMembershipChanged = true }
        }
        for value in updated {
            if let model = byID[value.id] {
                model.update(value)
            } else {
                let model = Model(value)
                byID[value.id] = model
                next.append(model)
                isRearranged = true
                isMembershipChanged = true
            }
        }
        if let order {
            let ordered = order.compactMap { byID[$0] }
            if !ordered.elementsEqual(next, by: ===) {
                let kept = Set(order)
                for model in next where !kept.contains(model.id) {
                    byID[model.id] = nil
                    isMembershipChanged = true
                }
                next = ordered
                isRearranged = true
            }
        }
        if isMembershipChanged { membershipStorage = byID }
        if isRearranged { modelsStorage = next }
        if isMembershipChanged { withMutation(keyPath: \.membership) {} }
        if isRearranged { withMutation(keyPath: \.models) {} }
    }

    /// Takes a whole new list, keeping the object of every record it still holds.
    func replace(with values: [Model.Value]) {
        let kept = Set(values.map(\.id))
        apply(
            updated: values, removed: modelsStorage.map(\.id).filter { !kept.contains($0) },
            order: values.map(\.id))
    }
}
