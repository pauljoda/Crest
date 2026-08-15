import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
enum MobileMediaPlaybackPolicy {
    static let inlineVideoScript = WKUserScript(
        source: """
            (() => {
              const keepInline = (root) => {
                if (root instanceof HTMLVideoElement) {
                  root.setAttribute('playsinline', '');
                  root.setAttribute('webkit-playsinline', '');
                }
                root.querySelectorAll?.('video').forEach((video) => {
                  video.setAttribute('playsinline', '');
                  video.setAttribute('webkit-playsinline', '');
                });
              };

              keepInline(document);
              new MutationObserver((records) => {
                records.forEach((record) => {
                  record.addedNodes.forEach((node) => {
                    if (node instanceof Element) keepInline(node);
                  });
                });
              }).observe(document.documentElement, { childList: true, subtree: true });
            })();
            """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )
}
