import SwiftUI

/// An emblem drawn from Crest's heraldic artwork, found by name.
struct BrowserCrestStudioHeraldicEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Controls

    func controls(in emblem: BrowserCrestStudioEmblem) -> AnyView {
        let context = emblem.context
        let search = emblem.search
        let matches = CrestSymbol.selectable.filter {
            search.isEmpty || String(localized: $0.title).localizedCaseInsensitiveContains(search)
        }
        let visible = search.isEmpty && !emblem.showsAll ? Array(matches.prefix(12)) : matches
        return AnyView(
            Group {
                BrowserCrestStudioTextField(title: "Find an emblem", symbol: "magnifyingglass", text: emblem.$search)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 8) {
                    ForEach(visible, id: \.self) { choice in
                        BrowserCrestStudioChoice(
                            title: choice.title, selected: context.value.crest.resolvedCharge == .heraldic(choice)
                        ) {
                            context.branding.editorUpdate {
                                $0.crest.symbol = choice
                                $0.crest.charge = nil
                                $0.hasCustomAppearance = true
                            }
                        } artwork: {
                            BrowserSpaceCrestIcon(
                                branding: context.preview {
                                    $0.crest.symbol = choice
                                    $0.crest.charge = nil
                                }, size: 52, rasterizesLayers: false
                            )
                            .equatable()
                        }
                    }
                }
                if search.isEmpty && matches.count > 12 {
                    Button(emblem.showsAll ? "Show fewer emblems" : "Browse all emblems (\(matches.count))") {
                        emblem.showsAll.toggle()
                    }
                    .buttonStyle(.borderless)
                } else if matches.isEmpty {
                    Text("No matching emblems. Try an SF Symbol or a monogram.").font(.caption).foregroundStyle(
                        .secondary)
                }
            })
    }

    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        .heraldic(emblem.context.value.crest.symbol)
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {}
}
