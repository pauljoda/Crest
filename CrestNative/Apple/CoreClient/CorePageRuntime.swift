import Foundation

#if os(macOS)
    import AppKit
    typealias CoreNativePageView = NSView
#else
    import UIKit
    typealias CoreNativePageView = UIView
#endif

/// Apple-side engine port. Views stay on the native path and never cross the C ABI.
@MainActor
protocol CorePageRuntime: AnyObject {
    var displayName: String { get }
    var isolationMode: String { get }
    var sessionDescription: String { get }
    var descriptor: Data { get throws }
    var send: ((String, [String: Any], CoreMessage?) -> Void)? { get set }
    func handle(_ message: CoreMessage)
    func dispose()
    func prepareToQuit(_ completion: @escaping @MainActor (Bool) -> Void)
    func cancelQuitPreparation()
    func nativeView(pageID: String) -> CoreNativePageView?
    func preparePresentation(pageID: String, windowID: String) -> Bool
    func didAttach(pageID: String, windowID: String)
    func didDetach(pageID: String)
}

extension CorePageRuntime {
    func prepareToQuit(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
    func cancelQuitPreparation() {}
    var isolationMode: String { "ephemeral" }
    var sessionDescription: String { "Tabs and Spaces are saved separately from Crest. Website data stays in memory." }
    func preparePresentation(pageID: String, windowID: String) -> Bool { true }
    func didAttach(pageID: String, windowID: String) {}
    func didDetach(pageID: String) {}
}
