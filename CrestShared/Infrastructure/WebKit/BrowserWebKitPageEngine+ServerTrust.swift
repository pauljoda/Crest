import Foundation
import WebKit

extension BrowserWebKitPageEngine {
    var serverTrust: SecTrust? { webView.serverTrust }
}
