import Foundation

/// What one lift carries from its start to its drop: what it lifts, as the
/// core reads a sidebar selection, and where the core would let it land,
/// asked once as the lift begins. A drop can still be refused when it lands,
/// since the session can change while the lift is held; its commit decides.
struct BrowserSidebarLiftPlan: Equatable, Sendable {
    // MARK: - Variables

    let selection: TabSelection
    /// Every list, Space, split and open tab the lift may drop on, with the
    /// rule that refuses each, or nil when the core could not answer.
    let targets: DropTargetList?

    // MARK: - Actions - Targets

    /// What the core says of dropping the lift on `target`: whether it may
    /// land there, the rule that refuses it, or that the core offers no such
    /// target for this lift at all.
    func verdict(on target: BrowserSidebarReorderTarget) -> BrowserSidebarDropVerdict {
        guard let targets else { return .unavailable }
        if let refusal = targets.refusal { return .refused(refusal) }
        switch target.kind {
        case .insert(let section, _, _):
            let list: ListDropTarget?
            switch section {
            case .tabs(let placement, let folderID):
                list = targets.lists.first { $0.section == placement && $0.folderID == folderID }
            case .folders(let parentID):
                list = targets.lists.first { $0.folderID == parentID && (parentID != nil || $0.section == .saved) }
            }
            return BrowserSidebarDropVerdict(list.map { $0.refusal })
        case .intoFolder(let folderID):
            return BrowserSidebarDropVerdict(targets.lists.first { $0.folderID == folderID }.map { $0.refusal })
        case .space(let assignment):
            return BrowserSidebarDropVerdict(
                targets.spaces.first { $0.spaceID == assignment.spaceID }.map { $0.refusal })
        case .splitInsert:
            return BrowserSidebarDropVerdict(targets.split.map { $0.refusal })
        case .createCurrentFolder(let tabID):
            return targets.folderAroundTabIDs.contains(tabID) ? .allowed : .unavailable
        }
    }
}

/// What the core says of one drop: it may land, a rule refuses it, or the
/// core offers no such target for the lift.
enum BrowserSidebarDropVerdict: Equatable, Sendable {
    case allowed
    case refused(Rejection)
    case unavailable

    /// A target the core listed, refused by `refusal` or allowed; a target it
    /// did not list, unavailable.
    init(_ listed: Rejection??) {
        switch listed {
        case .none: self = .unavailable
        case .some(.none): self = .allowed
        case .some(.some(let refusal)): self = .refused(refusal)
        }
    }
}

extension BrowserSidebarLiftPlan {
    /// Whether the core offers a drop on the zone for this lift at all, refused
    /// or not. A lift the core refuses outright is offered everywhere, so the
    /// preview can say why wherever it goes. The cards on show are the one
    /// exception: a refused join opens no placeholder among them, since the
    /// columns would make room for a card that never arrives.
    func offers(_ zone: BrowserSidebarReorderZone.Target) -> Bool {
        guard let targets, targets.refusal == nil else { return true }
        switch zone {
        case .section(.tabs(let placement, let folderID)):
            return targets.lists.contains { $0.section == placement && $0.folderID == folderID }
        case .section(.folders(let parentID)):
            return targets.lists.contains { $0.folderID == parentID }
        case .folder(let folderID):
            return targets.lists.contains { $0.folderID == folderID }
        case .currentTab(let tabID):
            return targets.folderAroundTabIDs.contains(tabID)
        case .space(let assignment):
            return targets.spaces.contains { $0.spaceID == assignment.spaceID }
        case .splitContent:
            return targets.split.map { $0.refusal == nil } ?? false
        }
    }
}
