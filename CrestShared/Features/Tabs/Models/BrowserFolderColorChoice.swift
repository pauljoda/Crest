import SwiftUI

struct BrowserFolderColorChoice: Identifiable, Equatable, Sendable {
    let title: String
    let value: BrowserSpaceBrandColor

    var id: BrowserSpaceBrandColor { value }
}
