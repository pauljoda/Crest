import SwiftUI

/// Dynamic Type-aware roles for Crest-authored content.
///
/// Crest sets its voice in SF Pro Rounded, heavy, for hero lines, titles,
/// buttons and small caps labels, over SF Pro for body and supporting copy.
/// Both ship with macOS and iOS, so nothing is embedded in the bundle.
enum CrestTypography {
    static let controlTitle = Font.body.weight(.medium)
    /// A button's title: rounded and bold.
    static let buttonTitle = Font.system(.body, design: .rounded, weight: .bold)
    /// A page's one large call to action: rounded and heavy.
    static let largeButtonTitle = Font.system(.title3, design: .rounded, weight: .heavy)
    /// A small caps label over a section or a group, in rounded heavy; set
    /// with `crestCapsLabel()`, which adds its tracking and color.
    static let capsLabel = Font.system(size: 12, weight: .heavy, design: .rounded)
    /// A settings or setup section's title: rounded heavy, at the size the
    /// platform gives section headers.
    static let sectionHeading = Font.system(.headline, design: .rounded, weight: .heavy)
    static let metadata = Font.caption
    static let compactMetadata = Font.caption2
    static let badge = Font.caption2.monospaced().weight(.semibold)

    /// Display type, rounded and heavy, at `size`, scaling with Dynamic Type
    /// as `style` does where the platform has it.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        #if os(iOS)
            let scaled = UIFontMetrics(forTextStyle: platformStyle(of: style)).scaledValue(for: size)
            return .system(size: scaled, weight: .heavy, design: .rounded)
        #else
            return .system(size: size, weight: .heavy, design: .rounded)
        #endif
    }

    /// Display type, rounded and heavy, at a fixed size, for layouts whose
    /// line breaks are composed by hand.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Body and supporting type in the system face.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    #if os(iOS)
        /// The UIKit text style matching `style`, for scaling a size by it.
        private static func platformStyle(of style: Font.TextStyle) -> UIFont.TextStyle {
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
    #endif

    // MARK: - Named display roles

    /// Title of a single page or pane inside a Crest-authored flow.
    static let displayPageSize: CGFloat = 24
    /// Heading that opens a group of rows inside a pane.
    static let displaySectionSize: CGFloat = 17

    static var displayPage: Font { display(displayPageSize, relativeTo: .title2) }
    static var displaySection: Font { display(displaySectionSize, relativeTo: .title3) }
}
