import SwiftUI

/// An emblem drawn from an SF Symbol.
struct BrowserCrestStudioSystemEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Controls

    func controls(in emblem: BrowserCrestStudioEmblem) -> AnyView {
        AnyView(BrowserSystemSymbolPicker(selection: emblem.$systemName))
    }

    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        .system(emblem.systemName)
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {
        let text = charge.text ?? ""
        if emblem.systemName != text { emblem.systemName = text }
    }
}
