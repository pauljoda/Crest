import SwiftUI
import UIKit

struct BrowserPlatformAppIconSettingsSection: View {
    @State private var selectedName = UIApplication.shared.alternateIconName
    @State private var isChanging = false
    @State private var errorMessage: String?

    var body: some View {
        CrestSettingsGroup(
            "App icon",
            settings: [resettable],
            footnote:
                "Choose a palette for Crest’s Home Screen icon. Your device controls its light, dark, tinted, or clear appearance."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 12)], spacing: 16) {
                iconChoice(name: nil, title: "Crest", preview: nil)
                ForEach(BrowserSpaceHousePalette.allCases, id: \.self) { palette in
                    let name = "Crest" + palette.rawValue.capitalized
                    iconChoice(name: name, title: LocalizedStringKey(palette.name), preview: name + "Preview")
                }
            }
            .padding(.vertical, 8)
            .disabled(isChanging || !UIApplication.shared.supportsAlternateIcons)
        }
        .onAppear { selectedName = UIApplication.shared.alternateIconName }
        .alert(
            "Couldn’t change app icon",
            isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
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
                errorMessage = String(localized: "Crest could not update its icon. Please try again.")
            }
        }
    }

    private func iconChoice(name: String?, title: LocalizedStringKey, preview: String?) -> some View {
        Button {
            select(name)
        } label: {
            VStack(spacing: 6) {
                Image(preview ?? "CrestPreview").resizable().scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(.rect(cornerRadius: 13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13)
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
