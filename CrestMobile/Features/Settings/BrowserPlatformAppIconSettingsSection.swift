import SwiftUI
import UIKit

struct BrowserPlatformAppIconSettingsSection: View {
    @State private var selectedName = UIApplication.shared.alternateIconName
    @State private var isChanging = false

    var body: some View {
        CrestSettingsGroup(
            "App icon",
            settings: [resettable]
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 12)], spacing: 16) {
                iconChoice(name: nil, title: "Crest")
                ForEach(SpaceHouse.all, id: \.self) { house in
                    iconChoice(name: house.appIconName, title: house.title)
                }
            }
            .padding(.vertical, 8)
            .disabled(isChanging || !UIApplication.shared.supportsAlternateIcons)
        }
        .onAppear { selectedName = UIApplication.shared.alternateIconName }
    }

    private var resettable: CrestResettableSetting {
        CrestResettableSetting(title: "App icon", isDefault: selectedName == nil) { select(nil) }
    }

    private func select(_ name: String?) {
        guard !isChanging, selectedName != name else { return }
        isChanging = true
        Task { @MainActor in
            defer { isChanging = false }
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                selectedName = UIApplication.shared.alternateIconName
            } catch {
                BrowserNoticeCenter.shared.post(.failure(String(localized: "Couldn’t change app icon")))
            }
        }
    }

    private func iconChoice(name: String?, title: LocalizedStringResource) -> some View {
        Button {
            select(name)
        } label: {
            VStack(spacing: 6) {
                BrowserPlatformAppIcon(name: name)
                    .frame(width: 58, height: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(selectedName == name ? Color.accentColor : .clear, lineWidth: 3)
                    }
                Text(title).font(.caption).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedName == name ? .isSelected : [])
        .accessibilityIdentifier("app-icon-" + (name ?? "default"))
    }

}
