import Foundation

/// Stores the core's saved site-permission document as opaque bytes. The
/// core reads and writes its format; storage never interprets it.
protocol BrowserSitePermissionPersisting: AnyObject {
    func loadDocument() -> Data?
    func saveDocument(_ document: Data)
}
