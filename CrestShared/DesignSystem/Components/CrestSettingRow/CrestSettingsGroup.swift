import SwiftUI

/// A titled group of settings that can put everything it holds back at once.
///
/// The group stays a native `Section` so the platform's own grouped form draws
/// the card and its insets. An icon and display heading introduce the preview
/// and controls, with one quiet Reset on the header's trailing edge. The Reset
/// keeps its place whether or not it is showing, so a header never changes
/// height and the cards below it never move.
struct CrestSettingsGroup<Preview: View, Content: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let settings: [CrestResettableSetting]
    private let footnote: LocalizedStringKey?
    private let preview: Preview
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        settings: [CrestResettableSetting] = [],
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.settings = settings
        self.footnote = footnote
        self.preview = preview()
        self.content = content()
    }

    var body: some View {
        Section {
            preview
            content
            if let footnote {
                CrestFormFootnote(footnote)
            }
        } header: {
            HStack(spacing: CrestSpacing.small) {
                CrestSettingsSectionHeading(title: title, systemImage: systemImage)
                Spacer(minLength: CrestSpacing.small)
                Button("Reset", action: settings.resetAll)
                    .buttonStyle(.crestTertiary)
                    .opacity(isModified ? 1 : 0)
                    .animation(
                        BrowserVisualAccessibilityPolicy.animation(CrestMotion.surface, reduceMotion: reduceMotion),
                        value: isModified
                    )
                    .disabled(!isModified)
                    .accessibilityHidden(!isModified)
                    .accessibilityLabel(Text("Reset \(Text(title)) to defaults"))
            }
        }
    }

    private var isModified: Bool { settings.isModified }
}

extension CrestSettingsGroup where Preview == EmptyView {
    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        settings: [CrestResettableSetting] = [],
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title, systemImage: systemImage, settings: settings, footnote: footnote,
            preview: { EmptyView() }, content: content
        )
    }
}

#if DEBUG
    #Preview("Group reset") {
        @Previewable @State var opacity = 0.65
        Form {
            CrestSettingsGroup(
                "Appearance", systemImage: "paintpalette",
                settings: [CrestSettingValue($opacity, default: 1).resettable("Opacity")],
                footnote: "Customize how your Space looks."
            ) {
                CrestIconTile(systemImage: "paintpalette.fill", color: .indigo)
            } content: {
                CrestSettingSlider("Opacity", value: CrestSettingValue($opacity, default: 1))
            }
        }.crestSettingsForm().frame(width: 420, height: 320)
    }
#endif
