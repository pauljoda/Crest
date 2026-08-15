import Foundation
import WebKit

/// What Crest does with one new-window request. `open` is the only disposition
/// that may adopt WebKit's pre-made web view, because adoption has to happen
/// while `createWebViewWith` is still on the stack.
enum BrowserPopupDisposition: Equatable {
    case open
    case deny
    case prompt
}
