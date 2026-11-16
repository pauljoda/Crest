import SwiftUI

/// The customization style every Space shows, as one preview button for each
/// style: a Crest window in the style's look, with its Space icons. Choosing
/// one gives every Space that follows it the style's look.
struct BrowserCustomizationStyleGroup: View {
    // MARK: - Variables

    let browser: BrowserStore
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        let style = CrestSettingValue(
            $appearance.customizationStyle, default: BrowserLookAndFeelDefaults.customizationStyle)
        let resettable = CrestResettableSetting(title: "Style", isDefault: style.isDefault) {
            withAnimation(CrestMotion.styleChange.unlessReducingMotion(reduceMotion)) {
                browser.chooseCustomizationStyle(BrowserLookAndFeelDefaults.customizationStyle)
            }
        }
        CrestSettingsGroup("Style", settings: [resettable]) {
            BrowserCustomizationStyleChoices(
                selection: appearance.customizationStyle, spaceIcons: appearance.chosenSpaceIcons
            ) { chosen in
                withAnimation(CrestMotion.styleChange.unlessReducingMotion(reduceMotion)) {
                    browser.chooseCustomizationStyle(chosen)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("customization-style")
        }
    }
}

/// The three styles as preview buttons in a row, each a Crest window in the
/// style's look with its Space icons, or the icons the person chose.
struct BrowserCustomizationStyleChoices<Badge: View>: View {
    // MARK: - Variables

    let selection: BrowserCustomizationStyle
    /// The Space icons the person chose, which every preview shows, or nil
    /// for each style's own.
    let spaceIcons: BrowserSpaceIconDisplay?
    /// The size of each button's face, or nil for the size settings use.
    var faceSize: CGFloat? = nil
    /// Whether the buttons run across a row or stack down a column.
    var axis: Axis = .horizontal
    let choose: (BrowserCustomizationStyle) -> Void
    /// What sits under a style's title, such as the one a Space follows.
    @ViewBuilder var badge: (BrowserCustomizationStyle) -> Badge

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat?

    // MARK: - Actions - Drawing

    var body: some View {
        let layout =
            axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: BrowserCustomizationStyleMetrics.spacing))
            : AnyLayout(VStackLayout(spacing: BrowserCustomizationStyleMetrics.spacing))
        layout {
            ForEach(BrowserCustomizationStyle.all) { style in
                VStack(spacing: 4) {
                    CrestPreviewButton(
                        title: Text(style.title), isSelected: style == selection,
                        previewSize: BrowserCustomizationStyleMetrics.previewSize, faceSize: shownFaceSize
                    ) {
                        choose(style)
                    } preview: {
                        BrowserOnboardingWindowPreview(
                            branding: style.look.previewBranding, symbol: style.look.previewSymbol,
                            name: String(localized: "Personal"), spaceIcons: spaceIcons ?? style.spaceIcons,
                            companionLook: style.look
                        ) {
                            EmptyView()
                        }
                    }
                    .accessibilityIdentifier("customization-style-\(style.name)")
                    badge(style)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .padding(.vertical, CrestSpacing.medium)
    }

    /// The face given, or else the settings size, made smaller where three
    /// would not fit across the row.
    private var shownFaceSize: CGFloat {
        if let faceSize { return faceSize }
        guard axis == .horizontal else {
            return sizeClass == .compact ? CrestPreviewButtonMetrics.compactFace : CrestPreviewButtonMetrics.regularFace
        }
        let preferred =
            sizeClass == .compact ? CrestPreviewButtonMetrics.compactFace : CrestPreviewButtonMetrics.regularFace
        guard let width else { return preferred }
        let fits = (width - 2 * BrowserCustomizationStyleMetrics.spacing) / 3
        return max(BrowserCustomizationStyleMetrics.smallestFace, min(preferred, fits))
    }
}

extension BrowserCustomizationStyleChoices where Badge == EmptyView {
    init(
        selection: BrowserCustomizationStyle, spaceIcons: BrowserSpaceIconDisplay?, faceSize: CGFloat? = nil,
        axis: Axis = .horizontal, choose: @escaping (BrowserCustomizationStyle) -> Void
    ) {
        self.init(selection: selection, spaceIcons: spaceIcons, faceSize: faceSize, axis: axis, choose: choose) { _ in
            EmptyView()
        }
    }
}

enum BrowserCustomizationStyleMetrics {
    /// The size a style's window is laid out at before it is drawn small.
    static let previewSize = CGSize(width: 520, height: 520)
    static let spacing: CGFloat = 20
    /// The smallest a style's button gets in a narrow row.
    static let smallestFace: CGFloat = 80
}
