import SwiftUI

/// Dynamic Type-aware roles for Crest-authored content.
///
/// Crest sets its voice in Allo at its roundest, heavy, for hero lines,
/// titles, buttons and small caps labels, over SF Pro for body and
/// supporting copy. Allo ships inside the app (``CrestDisplayFace``); SF Pro
/// ships with macOS and iOS. Each role reads the size its text style has now,
/// so text set in it follows the person's text size.
enum CrestTypography {
    static let controlTitle = Font.body.weight(.medium)
    /// A button's title: rounded and bold.
    static var buttonTitle: Font { display(.body, weight: .bold) }
    /// A compact button's title, as on a card in the sidebar: rounded and
    /// bold, a size down.
    static var compactButtonTitle: Font { display(.subheadline, weight: .bold) }
    /// A page's one large call to action: rounded and heavy.
    static var largeButtonTitle: Font { display(.title3, weight: .heavy) }
    /// A small caps label over a section or a group, in rounded heavy; set
    /// with `crestCapsLabel()`, which adds its tracking and color.
    static var capsLabel: Font { CrestDisplayFace.allo.font(size: 12, weight: .heavy) }
    /// A settings or setup section's title: rounded heavy, at the size the
    /// platform gives section headers.
    static var sectionHeading: Font { display(.headline, weight: .heavy) }
    /// A glyph alone on a control a finger presses, as on the phone's and
    /// iPad's chrome.
    static let touchControlGlyph = Font.system(size: 17, weight: .medium)
    /// Supporting copy at reading size, such as a guide's paragraphs.
    static var supportingBody: Font { sans(14, relativeTo: .body) }
    /// A short label in the system face, semibold: a small heading over a
    /// window, a choice's title, a text button or a Space chip.
    static var label: Font { sans(13, relativeTo: .body, weight: .semibold) }
    /// Small supporting copy: a note under a guide, a hint beside an action.
    static var note: Font { sans(12, relativeTo: .footnote) }
    /// The line under a page's hero title, as on setup's welcome.
    static var lead: Font { sans(20, relativeTo: .title3, weight: .medium) }
    static let metadata = Font.caption
    static let compactMetadata = Font.caption2
    static let badge = Font.caption2.monospaced().weight(.semibold)

    /// Display type, rounded and heavy, at `size`, scaling with Dynamic Type
    /// as `style` does where the platform has it.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        #if os(iOS)
            let scaled = UIFontMetrics(forTextStyle: platformStyle(of: style)).scaledValue(for: size)
            return CrestDisplayFace.allo.font(size: scaled, weight: .heavy)
        #else
            return CrestDisplayFace.allo.font(size: size, weight: .heavy)
        #endif
    }

    /// Display type, rounded and heavy, at a fixed size, for layouts whose
    /// line breaks are composed by hand.
    static func display(_ size: CGFloat) -> Font {
        CrestDisplayFace.allo.font(size: size, weight: .heavy)
    }

    /// System type at a fixed size, for an illustration composed at fixed
    /// sizes, such as the Settings sample page or a window preview. Copy a
    /// person reads takes a role, which follows their text size.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// System type at `size`, scaling with Dynamic Type as `style` does where
    /// the platform has it.
    private static func sans(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        #if os(iOS)
            let scaled = UIFontMetrics(forTextStyle: platformStyle(of: style)).scaledValue(for: size)
            return .system(size: scaled, weight: weight)
        #else
            return .system(size: size, weight: weight)
        #endif
    }

    /// Display type at the size `style` has now, which follows the person's
    /// text size where the platform has one.
    private static func display(_ style: Font.TextStyle, weight: CrestDisplayFace.Weight) -> Font {
        #if os(iOS)
            let size = UIFont.preferredFont(forTextStyle: platformStyle(of: style)).pointSize
        #else
            let size = NSFont.preferredFont(forTextStyle: platformStyle(of: style)).pointSize
        #endif
        return CrestDisplayFace.allo.font(size: size, weight: weight)
    }

    #if os(iOS)
        private typealias PlatformTextStyle = UIFont.TextStyle
    #else
        private typealias PlatformTextStyle = NSFont.TextStyle
    #endif

    /// The platform's text style matching `style`, for reading or scaling a
    /// size by it.
    private static func platformStyle(of style: Font.TextStyle) -> PlatformTextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }

    // MARK: - Named display roles

    /// Title of a single page or pane inside a Crest-authored flow.
    static let displayPageSize: CGFloat = 24
    /// Heading that opens a group of rows inside a pane.
    static let displaySectionSize: CGFloat = 17

    static var displayPage: Font { display(displayPageSize, relativeTo: .title2) }
    static var displaySection: Font { display(displaySectionSize, relativeTo: .title3) }
}
