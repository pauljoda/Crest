import SwiftUI

/// A row that opens and closes what it heads, such as a folder, a Split View
/// or a Space's saved tabs, drawn with no press feedback: the disclosure's own
/// motion answers the click, and a title that dims while pressed reads as a
/// flash beside it.
struct CrestDisclosureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension ButtonStyle where Self == CrestDisclosureButtonStyle {
    static var crestDisclosure: CrestDisclosureButtonStyle { CrestDisclosureButtonStyle() }
}
