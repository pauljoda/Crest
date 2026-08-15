import SwiftUI

struct BrowserSpaceSymbolArtworkIdentity: Equatable, Sendable {
    let branding: BrowserSpaceBranding
    let symbol: String
    let accessPolicy: BrowserSpaceAccessPolicy
    let size: CGFloat
    let lockSize: CGFloat
    let colorScheme: ColorScheme
    let displayScale: CGFloat
}
