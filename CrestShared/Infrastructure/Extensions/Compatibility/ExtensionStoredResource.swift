import Foundation

struct BrowserExtensionStoredResource {
    let resourceURL: URL
    let retainedAccess: AnyObject?
    let internalGrantedPermissions: Set<String>
    let capabilityBrokerGrantedPermissions: Set<String>
    let allowsInternalCapabilityBroker: Bool

    init(
        resourceURL: URL,
        retainedAccess: AnyObject? = nil,
        internalGrantedPermissions: Set<String> = [],
        capabilityBrokerGrantedPermissions: Set<String> = [],
        allowsInternalCapabilityBroker: Bool = false
    ) {
        self.resourceURL = resourceURL
        self.retainedAccess = retainedAccess
        self.internalGrantedPermissions = internalGrantedPermissions
        self.capabilityBrokerGrantedPermissions =
            capabilityBrokerGrantedPermissions
        self.allowsInternalCapabilityBroker = allowsInternalCapabilityBroker
    }
}
