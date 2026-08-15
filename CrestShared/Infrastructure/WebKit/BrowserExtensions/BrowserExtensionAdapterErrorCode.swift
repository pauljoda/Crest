import Foundation
import WebKit

enum BrowserExtensionAdapterErrorCode: Int {
    case tabUnavailable = 1
    case windowUnavailable
    case crossSpaceRequest
    case unsupportedOperation
    case optionsPageUnavailable
}
