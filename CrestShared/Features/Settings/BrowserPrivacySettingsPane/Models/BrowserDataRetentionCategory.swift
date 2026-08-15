import Foundation

enum BrowserDataRetentionCategory: String, CaseIterable, Equatable, Identifiable,
    Sendable
{
    case history
    case archive
    case downloads

    var id: Self { self }
}
