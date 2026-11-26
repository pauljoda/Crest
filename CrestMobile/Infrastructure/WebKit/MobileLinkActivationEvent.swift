import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

// MARK: - Types

/// Where a press on a link is.
enum MobileLinkPressPhase: String, Decodable {
    case began
    /// The press lasted long enough to open Peek.
    case held
    case ended
    case cancelled
}

struct MobileLinkActivationEvent {
    // MARK: - Types

    private struct WirePayload: Decodable {
        let phase: MobileLinkPressPhase
        let pressID: String
        let href: String?
        let label: String?
        let minX: Double?
        let minY: Double?
        let width: Double?
        let height: Double?
        let touchX: Double?
        let touchY: Double?
    }

    // MARK: - Variables

    let phase: MobileLinkPressPhase
    let pressID: String
    let destinationURL: URL?
    let label: String
    let normalizedSourceRect: CGRect?
    let normalizedTouchPoint: CGPoint?

    // MARK: - Initializers

    init?(body: Any) {
        guard JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let payload = try? JSONDecoder().decode(WirePayload.self, from: data)
        else { return nil }

        phase = payload.phase
        pressID = payload.pressID
        destinationURL = payload.href.flatMap(URL.init(string:))
        label = payload.label ?? ""

        if let minX = payload.minX,
            let minY = payload.minY,
            let width = payload.width,
            let height = payload.height
        {
            normalizedSourceRect = CGRect(x: minX, y: minY, width: width, height: height)
        } else {
            normalizedSourceRect = nil
        }

        if let touchX = payload.touchX, let touchY = payload.touchY {
            normalizedTouchPoint = CGPoint(x: touchX, y: touchY)
        } else {
            normalizedTouchPoint = nil
        }
    }

    // MARK: - Actions - Peek

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
}
