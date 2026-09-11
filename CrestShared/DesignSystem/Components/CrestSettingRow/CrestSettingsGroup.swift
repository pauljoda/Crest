import SwiftUI

/// A titled group of settings that can put everything it holds back at once.
///
/// The group stays a native `Section` so the platform's own grouped form draws
/// the card, its insets, and its header. What it adds is a preview slot at the
/// top of the card and one quiet Reset on the header's trailing edge. The Reset
/// keeps its place whether or not it is showing, so a header never changes
/// height and the cards below it never move.
struct CrestSettingsGroup<Preview: View, Content: View>: View {
    private let title: LocalizedStringKey
    private let settings: [CrestResettableSetting]
    private let footnote: LocalizedStringKey?
    private let preview: Preview
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ title: LocalizedStringKey,
        settings: [CrestResettableSetting] = [],
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
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
                Text(title)
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
        settings: [CrestResettableSetting] = [],
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, settings: settings, footnote: footnote, preview: { EmptyView() }, content: content)
    }
}
