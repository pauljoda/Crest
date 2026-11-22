import Foundation

/// The extensions Open Next Extension steps through, and the step each press
/// takes: the pinned ones in the strip's order, then the others the page
/// offers, each once. A press opens the first popup when none of these shows,
/// the next one while one does, and closes the popup after the last.
struct BrowserExtensionPopupCycle: Equatable {
    // MARK: - Types

    enum Step: Equatable {
        /// Opens the popup of the extension the identifier names.
        case open(String)
        /// Closes the popup that shows.
        case close
    }

    // MARK: - Variables

    /// The extensions in the order the presses open their popups.
    let ids: [String]

    var isEmpty: Bool { ids.isEmpty }

    // MARK: - Initializers

    /// The cycle over `pinned`, in the strip's order, then `others`, keeping
    /// each extension's first place, so one the pin list and the page both
    /// name comes once.
    init(pinned: [String], others: [String]) {
        var seen = Set<String>()
        ids = (pinned + others).filter { seen.insert($0).inserted }
    }

    // MARK: - Actions - Stepping

    /// The step a press takes while `shown`'s popup shows, or nil with no
    /// extension to open.
    func step(showing shown: String?) -> Step? {
        guard let first = ids.first else { return nil }
        guard let shown, let index = ids.firstIndex(of: shown) else { return .open(first) }
        return ids.indices.contains(index + 1) ? .open(ids[index + 1]) : .close
    }
}
