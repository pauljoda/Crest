import CoreGraphics

/// Where the Look and Feel pane puts its live preview.
enum BrowserLookAndFeelLayoutMode: Equatable {
    /// One window crop pinned beside a scrolling form.
    case pinnedPreview
    /// A preview at the top of each group's own card.
    case inlinePreviews
}

/// The two columns of the pinned layout.
struct BrowserLookAndFeelColumns: Equatable {
    let preview: CGFloat
    let form: CGFloat
}

/// Whether the pane has room for a pinned preview beside its controls, and how
/// the two share the width they get.
///
/// The form is the fixed partner: it never grows past the readable width the
/// other panes use, so its controls stay where a reader left them. Everything
/// beyond that goes to the preview, whose page edge simply shows more of the
/// page as the window widens.
enum BrowserLookAndFeelLayoutPolicy {
    /// The narrowest crop that still shows the whole sidebar and a readable
    /// page edge, plus the narrowest form column that fits a title beside a
    /// segmented control.
    static let previewMinimumWidth: CGFloat = 260
    static let formMinimumWidth: CGFloat = 356
    static let previewLeadingPadding: CGFloat = CrestSpacing.extraExtraLarge
    static let pinnedPreviewMinimumWidth: CGFloat = previewMinimumWidth + formMinimumWidth + previewLeadingPadding
    static let formMaximumWidth: CGFloat = BrowserSettingsVisualPolicy.maximumReadableContentWidth

    static func mode(forWidth width: CGFloat) -> BrowserLookAndFeelLayoutMode {
        width >= pinnedPreviewMinimumWidth ? .pinnedPreview : .inlinePreviews
    }

    static func columns(forWidth width: CGFloat) -> BrowserLookAndFeelColumns {
        let available = max(0, width - previewLeadingPadding)
        let form = min(formMaximumWidth, max(formMinimumWidth, available - previewMinimumWidth))
        return BrowserLookAndFeelColumns(preview: max(0, available - form), form: form)
    }
}
