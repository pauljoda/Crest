struct BrowserSidebarClearHistoryConfirmation: Equatable, Sendable {
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceName: String

    var spaceID: SpaceID { assignment.spaceID }
}
