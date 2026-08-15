import Foundation

struct BrowserPeekRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let sourceTabID: TabID
    let sourceTitle: String
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let trigger: BrowserPeekTrigger
    let sourcePresentation: BrowserPeekSourcePresentation?

    var spaceID: SpaceID { spaceAssignment.spaceID }

    var assignment: BrowserSpaceRuntimeAssignment { spaceAssignment }

    init(
        id: UUID = UUID(),
        url: URL,
        sourceTabID: TabID,
        sourceTitle: String,
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        trigger: BrowserPeekTrigger,
        sourcePresentation: BrowserPeekSourcePresentation? = nil
    ) {
        self.id = id
        self.url = url
        self.sourceTabID = sourceTabID
        self.sourceTitle = sourceTitle
        self.spaceAssignment = spaceAssignment
        self.trigger = trigger
        self.sourcePresentation = sourcePresentation
    }
}
