import SwiftUI

/// No emblem on the crest.
struct BrowserCrestStudioNoEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Controls

    func controls(in emblem: BrowserCrestStudioEmblem) -> AnyView {
        AnyView(EmptyView())
    }

    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        CrestCharge.none
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {}
}
