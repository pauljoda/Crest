import Foundation

struct BrowserQuickWindowPresentationIdentity: Hashable {
    let requestID: UUID
    private let browserID: ObjectIdentifier
    private let pagePoolID: ObjectIdentifier

    init(
        request: BrowserQuickWindowRequest,
        context: BrowserQuickWindowBrowsingContext
    ) {
        requestID = request.id
        browserID = ObjectIdentifier(context.browser)
        pagePoolID = ObjectIdentifier(context.pages)
    }
}
