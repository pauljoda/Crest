import Foundation
import WebKit

struct BrowserNativeMessagingHostManifest: Equatable {
    let name: String
    let executableURL: URL
    let arguments: [String]

    init(
        name: String,
        executableURL: URL,
        arguments: [String] = []
    ) {
        self.name = name
        self.executableURL = executableURL
        self.arguments = arguments
    }
}
