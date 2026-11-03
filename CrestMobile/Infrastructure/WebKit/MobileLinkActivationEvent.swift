import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

// MARK: - Types

/// Where a press on a link is.
enum MobileLinkPressPhase: String {
    case began
    case ended
    case cancelled
}

struct MobileLinkActivationEvent {

    let phase: MobileLinkPressPhase
    let pressID: String
    let destinationURL: URL?
    let label: String
    let normalizedSourceRect: CGRect?
    let normalizedTouchPoint: CGPoint?

    init?(body: Any) {
        guard let values = body as? [String: Any],
            let phase = (values["phase"] as? String).flatMap(MobileLinkPressPhase.init(rawValue:)),
            let pressID = values["pressID"] as? String
        else { return nil }

        self.phase = phase
        self.pressID = pressID
        destinationURL = (values["href"] as? String).flatMap(URL.init(string:))
        label = values["label"] as? String ?? ""

        if let minX = Self.number(values["minX"]),
            let minY = Self.number(values["minY"]),
            let width = Self.number(values["width"]),
            let height = Self.number(values["height"])
        {
            normalizedSourceRect = CGRect(
                x: minX,
                y: minY,
                width: width,
                height: height
            )
        } else {
            normalizedSourceRect = nil
        }

        if let touchX = Self.number(values["touchX"]),
            let touchY = Self.number(values["touchY"])
        {
            normalizedTouchPoint = CGPoint(x: touchX, y: touchY)
        } else {
            normalizedTouchPoint = nil
        }
    }

    /// The Peek holding this press on a link opens, from the page described
    /// by `context`.
    func peekRequest(
        context: BrowserPageNavigationContext?,
        sourcePresentation: BrowserPeekSourcePresentation?
    ) -> BrowserPeekRequest? {
        guard let destinationURL, ExternalWebLink.accepts(destinationURL), let context else { return nil }
        return BrowserPeekRequest(
            url: destinationURL,
            sourceTabID: context.tabID,
            sourceTitle: context.title,
            spaceAssignment: context.assignment,
            trigger: .longPress,
            sourcePresentation: sourcePresentation
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return value as? Double
    }
}
