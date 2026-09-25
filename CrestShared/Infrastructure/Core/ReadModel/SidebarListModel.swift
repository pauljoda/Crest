import Foundation
import Observation

/// One list a Space's sidebar shows together, the top level of a section or
/// the inside of a folder, observed on its own: a move redraws only the list
/// it moves within, and a new title or address redraws no list. Its rows are
/// stored before they are announced; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class SidebarListModel {
    // MARK: - Variables

    /// The rows in order. A collapsed folder's list still holds its rows.
    private(set) var rows: [SidebarRow] {
        get { observed(\.rowsStorage, as: \.rows) }
        set { publish(newValue, into: \.rowsStorage, as: \.rows) }
    }
    @ObservationIgnored private var rowsStorage: [SidebarRow]

    // MARK: - Initializers

    init(rows: [SidebarRow] = []) {
        rowsStorage = rows
    }

    // MARK: - Actions - Changes

    /// Takes the list's rows again, announcing them only when they differ.
    func update(_ rows: [SidebarRow]) {
        self.rows = rows
    }
}

extension SidebarListModel: BrowserStoreFirstObservable {}
