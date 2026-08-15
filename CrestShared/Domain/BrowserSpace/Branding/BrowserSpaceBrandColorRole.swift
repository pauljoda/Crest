import Foundation

enum BrowserSpaceBrandColorRole: Int, CaseIterable, Equatable, Identifiable, Sendable {
    case background
    case primary
    case secondary

    var id: Int { rawValue }
}
