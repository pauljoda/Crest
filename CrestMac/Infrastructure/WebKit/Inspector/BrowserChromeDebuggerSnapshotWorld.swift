import Foundation
import ObjectiveC
import WebKit

/// A named, inspectable world lets DOM snapshots use native DOM accessors and
/// then resolve those exact objects through Inspector. The configuration is
/// local to this world; it never opens shadow roots to page/extension scripts.
@MainActor
enum BrowserChromeDebuggerSnapshotWorld {
    static func make(name: String) throws -> WKContentWorld {
        guard let type = NSClassFromString("_WKContentWorldConfiguration") as? NSObject.Type else {
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand("DOMSnapshot.captureSnapshot")
        }
        let configuration = type.init()
        let settings: [(String, String, Any)] = [
            ("setName:", "name", name),
            ("setAllowAccessToClosedShadowRoots:", "allowAccessToClosedShadowRoots", true),
            ("setDisableLegacyBuiltinOverrides:", "disableLegacyBuiltinOverrides", true),
        ]
        for (setter, key, value) in settings {
            guard configuration.responds(to: NSSelectorFromString(setter)) else {
                throw BrowserChromeDebuggerProtocolError.unsupportedCommand("DOMSnapshot.captureSnapshot")
            }
            configuration.setValue(value, forKey: key)
        }
        // Newer WebKit distinguishes internal worlds from inspectable user
        // worlds. Older named configurations are inspectable by default.
        if configuration.responds(to: NSSelectorFromString("setInspectable:")) {
            configuration.setValue(true, forKey: "inspectable")
        }
        let selector = NSSelectorFromString("_worldWithConfiguration:")
        guard let method = class_getClassMethod(WKContentWorld.self, selector) else {
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand("DOMSnapshot.captureSnapshot")
        }
        let make = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>).self)
        guard
            let world = make(WKContentWorld.self as AnyObject, selector, configuration).takeUnretainedValue()
                as? WKContentWorld
        else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        return world
    }
}
