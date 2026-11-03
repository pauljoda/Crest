import SwiftUI

struct BrowserPlatformAppIconSettingsSection: View {
    @AppStorage(BrowserMacAppIconAssets.preferenceKey, store: BrowserMacDockTile.shared.defaults)
    private var selectedName = ""
    @State private var appearanceRevision = 0
    @State private var appearanceObserver: BrowserMacAppIconAppearanceObserver?

    var body: some View {
        CrestSettingsGroup(
            "App icon",
            settings: [resettable]
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 12)], spacing: 16) {
                iconChoice(name: "", title: "Crest", preview: "CrestPreview")
                ForEach(SpaceHouse.all, id: \.self) { house in
                    iconChoice(name: house.appIconName, title: house.title, preview: house.appIconName + "Preview")
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            appearanceObserver = BrowserMacAppIconAppearanceObserver { appearanceRevision += 1 }
        }
        .onDisappear {
            appearanceObserver?.stop()
            appearanceObserver = nil
        }
    }

    private var resettable: CrestResettableSetting {
        CrestResettableSetting(title: "App icon", isDefault: selectedName.isEmpty) { select("") }
    }

    /// Wears the icon `name` names, or says in the window that it couldn't.
    private func select(_ name: String) {
        guard !BrowserMacDockTile.shared.select(name) else { return }
        BrowserNoticeCenter.shared.post(.failure(String(localized: "Couldn’t change app icon")))
    }

    private func iconChoice(name: String, title: LocalizedStringResource, preview: String) -> some View {
        CrestSelectableCard(isSelected: selectedName == name, accessibilityLabel: Text(title), density: .compact) {
            select(name)
        } content: {
            VStack(spacing: 6) {
                Image(
                    nsImage: name.isEmpty
                        ? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
                        : BrowserMacAppIconAssets.image(named: name, in: .main) ?? NSImage()
                )
                .resizable().scaledToFit()
                .id(appearanceRevision)
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 13))
                Text(title).font(.caption).foregroundStyle(.primary)
            }
        }
        .accessibilityIdentifier("app-icon-" + (name.isEmpty ? "default" : name))
    }
}
