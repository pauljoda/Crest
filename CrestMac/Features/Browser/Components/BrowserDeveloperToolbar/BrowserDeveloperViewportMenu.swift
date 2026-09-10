import SwiftUI

struct BrowserDeveloperViewportMenu: View {
    let page: BrowserPage
    @State private var showsCustomSize = false
    @State private var width = ""
    @State private var height = ""

    private enum Selection: Hashable {
        case normal
        case preset(BrowserDeveloperViewport)
        case custom
    }

    var body: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            viewportMenu
            if showsCustomSize {
                BrowserDeveloperCustomViewportFields(width: $width, height: $height) {
                    guard let viewport = BrowserDeveloperViewport.customSize(width: width, height: height) else {
                        return
                    }
                    page.developerViewport = viewport
                }
            }
        }
        .onAppear(perform: synchronizeCustomSize)
        .onChange(of: page.developerViewport) { _, _ in
            synchronizeCustomSize()
        }
    }

    private var viewportMenu: some View {
        Menu {
            Picker(
                "Viewport",
                selection: Binding(
                    get: {
                        if showsCustomSize { return Selection.custom }
                        return page.developerViewport.map(Selection.preset) ?? .normal
                    },
                    set: { selection in
                        switch selection {
                        case .normal:
                            showsCustomSize = false
                            page.developerViewport = nil
                        case .preset(let viewport):
                            showsCustomSize = false
                            page.developerViewport = viewport
                        case .custom:
                            if !showsCustomSize { populateCustomSize() }
                            showsCustomSize = true
                        }
                    }
                )
            ) {
                Label("Normal — Preview Off", systemImage: "rectangle")
                    .tag(Selection.normal)
                ForEach(BrowserDeveloperViewport.presets) { viewport in
                    Label("\(viewport.title) — \(viewport.dimensions)", systemImage: viewport.systemImage)
                        .tag(Selection.preset(viewport))
                }
                Label("Custom", systemImage: "ruler")
                    .tag(Selection.custom)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Viewport Preview", systemImage: "macbook.and.iphone")
                .labelStyle(.iconOnly)
                .frame(height: BrowserDeveloperToolbarMetrics.buttonSize)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(page.developerViewport == nil ? Color.primary : Color.accentColor)
        .help("Viewport Preview")
        .accessibilityLabel("Viewport Preview")
        .accessibilityValue(
            showsCustomSize ? String(localized: "Custom") : page.developerViewport?.title ?? String(localized: "Off")
        )
        .accessibilityIdentifier("developer-viewport-menu")
    }

    private func synchronizeCustomSize() {
        showsCustomSize = page.developerViewport?.isCustom == true
        if showsCustomSize { populateCustomSize() }
    }

    private func populateCustomSize() {
        let size = page.developerViewport?.size ?? page.webView.bounds.size
        width = String(Int(size.width.rounded()))
        height = String(Int(size.height.rounded()))
    }
}
