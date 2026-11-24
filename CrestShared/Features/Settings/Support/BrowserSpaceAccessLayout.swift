import SwiftUI

enum BrowserSpaceAccessLayout {
    static let maximumContentWidth: CGFloat = 400
    static let maximumActionWidth: CGFloat = 280
    static let iconSize: CGFloat = 64
    /// The Space's name, in Crest's rounded display type.
    static let nameSize: CGFloat = 28
    /// How faintly the Space's background shows behind the lock, and how
    /// much fainter on an opaque canvas when transparency is reduced.
    static let backgroundOpacity = 0.1
    static let opaqueBackgroundOpacity = 0.04
}
