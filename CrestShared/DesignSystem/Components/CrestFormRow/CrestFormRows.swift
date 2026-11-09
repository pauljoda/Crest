import SwiftUI

/// The rows of a form section that can hold hundreds, such as a Space's saved
/// sites or passwords: one row for each element, as `ForEach` would make
/// them, but only for the rows on screen once there are more than
/// `lazilyAbove`, where the platform's form would otherwise make every one.
struct CrestFormRows<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    // MARK: - Variables

    private let data: Data
    private let id: KeyPath<Data.Element, ID>
    private let lazilyAbove: Int
    private let row: (Data.Element) -> Row

    // MARK: - Initializers

    /// - Parameter lazilyAbove: How many rows the section holds before only
    ///   the ones on screen are made. A form scrolls a few dozen light rows
    ///   more smoothly when they are all made; rows that are slow to make,
    ///   such as cards full of controls, are worth making lazily from the first.
    init(
        _ data: Data, id: KeyPath<Data.Element, ID>, lazilyAbove: Int = 100,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) {
        self.data = data
        self.id = id
        self.lazilyAbove = lazilyAbove
        self.row = row
    }

    init(_ data: Data, lazilyAbove: Int = 100, @ViewBuilder row: @escaping (Data.Element) -> Row)
    where Data.Element: Identifiable, ID == Data.Element.ID {
        self.init(data, id: \.id, lazilyAbove: lazilyAbove, row: row)
    }

    var body: some View {
        CrestPlatformFormRows(data: data, id: id, lazilyAbove: lazilyAbove, row: row)
    }
}
