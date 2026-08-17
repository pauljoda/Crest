import Foundation

@MainActor
protocol BrowserExtensionPageSelectionProviding: AnyObject {
    func prepareExtensionSelection(session: BrowserSession)
    func select(session: BrowserSession)
}
