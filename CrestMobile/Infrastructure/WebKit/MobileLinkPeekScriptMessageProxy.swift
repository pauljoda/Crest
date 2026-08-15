import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MobileLinkPeekScriptMessageProxy: NSObject, WKScriptMessageHandler {
    var receive: @MainActor (WKScriptMessage) -> Void = { _ in }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receive(message)
    }
}
