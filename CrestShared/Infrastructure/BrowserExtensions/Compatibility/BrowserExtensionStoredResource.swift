import Foundation

struct BrowserExtensionStoredResource {
    let resourceURL: URL
    let retainedAccess: AnyObject?

    init(
        resourceURL: URL,
        retainedAccess: AnyObject? = nil
    ) {
        self.resourceURL = resourceURL
        self.retainedAccess = retainedAccess
    }
}
