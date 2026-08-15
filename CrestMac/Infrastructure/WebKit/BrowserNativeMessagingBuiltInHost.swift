import Foundation

struct BrowserNativeMessagingBuiltInHost: Equatable {
    let name: String
    let extensionID: BrowserChromeExtensionID
    let executableURL: URL
}
