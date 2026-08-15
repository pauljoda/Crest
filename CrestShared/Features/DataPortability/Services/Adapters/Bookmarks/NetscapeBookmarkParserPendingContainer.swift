import Foundation

enum NetscapeBookmarkParserPendingContainer {
    case folder(draftIndex: Int, id: UUID)
    case space(draftIndex: Int)
}
