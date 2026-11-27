import SwiftUI

/// A titled group of settings that can put everything it holds back at once.
///
/// The group stays a native `Section` so the platform's own grouped form draws
/// the box and its insets. One quiet Reset sits on the header's trailing edge.
/// The Reset keeps its place whether or not it is showing, so a header never
/// changes height and the boxes below it never move.
struct CrestSettingsGroup<Preview: View, Content: View>: View {
    private let title: LocalizedStringKey
    private let settings: [CrestResettableSetting]
    private let footnote: LocalizedStringKey?
    /// Whether the group draws its heading, preview and footer. A group with
    /// nothing to show for part of a page stays a section whose rows have
    /// all hidden themselves, rather than leaving the form, so a scroll can
    /// still find it and the sections around it by their `id`s.
    private let isShown: Bool
    private let preview: Preview
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ title: LocalizedStringKey,
        settings: [CrestResettableSetting] = [],
        footnote: LocalizedStringKey? = nil,
        isShown: Bool = true,
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.settings = settings
        self.footnote = footnote
        self.isShown = isShown
        self.preview = preview()
        self.content = content()
    }

    var body: some View {
        Section {
            if isShown { preview }
            content
        } header: {
            // Collapsed rather than left out: a heading behind an `if`
            // keeps a scroll from finding any section after it by `id`.
            header
                .frame(height: isShown ? nil : 0)
                .opacity(isShown ? 1 : 0)
                .accessibilityHidden(!isShown)
        } footer: {
            if isShown, let footnote {
                CrestFormFootnote(footnote)
            }
        }
    }

    private var header: some View {
        HStack(spacing: CrestSpacing.small) {
            CrestSettingsSectionHeading(title: title)
            Spacer(minLength: CrestSpacing.small)
            Button("Reset", action: settings.resetAll)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .opacity(isModified ? 1 : 0)
                .animation(
                    CrestMotion.surface.unlessReducingMotion(reduceMotion),
                    value: isModified
                )
                .disabled(!isModified)
                .accessibilityHidden(!isModified)
                .accessibilityLabel(Text("Reset \(Text(title)) to defaults"))
        }
    }

    private var isModified: Bool { settings.isModified }
}

extension CrestSettingsGroup where Preview == EmptyView {
    init(
        _ title: LocalizedStringKey,
        settings: [CrestResettableSetting] = [],
        footnote: LocalizedStringKey? = nil,
        isShown: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title, settings: settings, footnote: footnote, isShown: isShown,
            preview: { EmptyView() }, content: content
        )
    }
}

#if DEBUG
    #Preview("Group reset") {
        @Previewable @State var opacity = 0.65
        Form {
            CrestSettingsGroup(
                "Appearance",
                settings: [CrestSettingValue($opacity, default: 1).resettable("Opacity")]
            ) {
                CrestSettingSlider("Opacity", value: CrestSettingValue($opacity, default: 1))
            }
        }.crestSettingsForm().frame(width: 420, height: 320)
    }
#endif
