import Foundation

struct BrowserExtensionStoredResource {
    let resourceURL: URL
    let retainedAccess: AnyObject?
    let internalGrantedPermissions: Set<String>

    init(
        resourceURL: URL,
        retainedAccess: AnyObject? = nil,
        internalGrantedPermissions: Set<String> = []
    ) {
        self.resourceURL = resourceURL
        self.retainedAccess = retainedAccess
        self.internalGrantedPermissions = internalGrantedPermissions
    }
}
