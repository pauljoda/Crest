import UIKit

extension BrowserTransientCardArrangement {
    /// The arrangement this device's screen has room for.
    ///
    /// A phone has no room to float a card, so its overlay fills the safe area
    /// and is pushed away with a thumb; a tablet has room to leave the scrim
    /// showing and let a tap on it close the card. Idiom is read here, in the
    /// shell that owns UIKit, and never inside the shared surface.
    static var current: BrowserTransientCardArrangement {
        UIDevice.current.userInterfaceIdiom == .phone ? .sheet : .canvas
    }
}
