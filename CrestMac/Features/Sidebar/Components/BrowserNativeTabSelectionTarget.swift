import AppKit
import SwiftUI

struct BrowserNativeTabSelectionTarget: NSViewRepresentable {
    let itemID: BrowserSelectionItemID
    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment

    func makeNSView(context: Context) -> TargetView { TargetView() }

    func updateNSView(_ view: TargetView, context: Context) {
        view.itemID = itemID
        view.browser = browser
        view.assignment = assignment
    }

    final class TargetView: NSView {
        private static let targets = NSHashTable<TargetView>.weakObjects()
        weak var browser: BrowserStore?
        var itemID: BrowserSelectionItemID?
        var tabID: TabID? {
            get { itemID?.tabID }
            set { itemID = newValue.map(BrowserSelectionItemID.tab) }
        }
        var assignment: BrowserSpaceRuntimeAssignment?

        override init(frame: NSRect) {
            super.init(frame: frame)
            Self.targets.add(self)
        }

        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        static func item(
            at windowPoint: NSPoint, in window: NSWindow, browser: BrowserStore,
            assignment: BrowserSpaceRuntimeAssignment
        ) -> BrowserSelectionItemID? {
            matching(browser: browser, assignment: assignment)
                .filter {
                    let point = $0.convert(windowPoint, from: nil)
                    return $0.window === window && $0.bounds.contains(point) && $0.visibleRect.contains(point)
                }
                // A split container also covers its children; the actual row wins.
                .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?.itemID
        }

        static func orderedItems(
            browser: BrowserStore, assignment: BrowserSpaceRuntimeAssignment
        ) -> [BrowserSelectionItemID]? {
            let views = matching(browser: browser, assignment: assignment)
            guard
                let window = views.first(where: { $0.window?.isKeyWindow == true })?.window
                    ?? views.first?.window
            else { return nil }
            return views.filter { $0.window === window }.sorted {
                let first = $0.convert($0.bounds, to: nil)
                let second = $1.convert($1.bounds, to: nil)
                if abs(first.maxY - second.maxY) > 2 { return first.maxY > second.maxY }
                return first.minX < second.minX
            }.compactMap(\.itemID)
        }

        static func tab(
            at point: NSPoint, in window: NSWindow, browser: BrowserStore,
            assignment: BrowserSpaceRuntimeAssignment
        ) -> TabID? {
            item(at: point, in: window, browser: browser, assignment: assignment)?.tabID
        }

        private static func matching(
            browser: BrowserStore, assignment: BrowserSpaceRuntimeAssignment
        ) -> [TargetView] {
            targets.allObjects.filter {
                $0.browser === browser && $0.assignment == assignment && $0.window != nil
                    && !$0.isHiddenOrHasHiddenAncestor && !$0.bounds.isEmpty
            }
        }
    }
}
