import SwiftUI

/// An emblem of one or two letters in a chosen style.
struct BrowserCrestStudioMonogramEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Controls

    func controls(in emblem: BrowserCrestStudioEmblem) -> AnyView {
        AnyView(
            Group {
                BrowserCrestStudioTextField(title: "One or two letters", text: emblem.$monogram)
                Picker("Letter style", selection: emblem.$monogramStyle) {
                    Text("Serif").tag(CrestMonogramStyle.serif)
                    Text("Sans").tag(CrestMonogramStyle.sans)
                }.pickerStyle(.segmented)
            })
    }

    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        .monogram(emblem.monogram, emblem.monogramStyle)
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {
        let text = charge.text ?? ""
        if emblem.monogram != text { emblem.monogram = text }
        emblem.monogramStyle = charge.style ?? .serif
    }
}
