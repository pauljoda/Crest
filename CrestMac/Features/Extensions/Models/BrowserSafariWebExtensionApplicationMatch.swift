import Foundation

struct BrowserSafariWebExtensionApplicationMatch:
    Equatable,
    Identifiable,
    Sendable
{
    let applicationURL: URL
    let applicationDisplayName: String
    let descriptors: [BrowserSafariWebExtensionAppDescriptor]

    var id: URL { applicationURL }
}
