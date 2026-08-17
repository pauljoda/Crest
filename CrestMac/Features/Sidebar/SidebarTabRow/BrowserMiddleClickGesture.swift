import AppKit
import SwiftUI

struct BrowserMiddleClickGesture: NSGestureRecognizerRepresentable {
    let perform: @MainActor () -> Void

    func makeNSGestureRecognizer(context: Context) -> NSClickGestureRecognizer {
        let recognizer = NSClickGestureRecognizer()
        recognizer.buttonMask = 1 << 2
        recognizer.numberOfClicksRequired = 1
        return recognizer
    }

    func handleNSGestureRecognizerAction(
        _ recognizer: NSClickGestureRecognizer,
        context: Context
    ) {
        guard recognizer.state == .ended else { return }
        perform()
    }
}

enum BrowserTabMiddleClickAction: Equatable {
    case close
    case unload
}

enum BrowserTabMiddleClickPolicy {
    static func action(for placement: TabPlacement) -> BrowserTabMiddleClickAction {
        placement == .current ? .close : .unload
    }
}

extension View {
    func browserOnMiddleClick(
        perform: @escaping @MainActor () -> Void
    ) -> some View {
        gesture(BrowserMiddleClickGesture(perform: perform))
    }
}
