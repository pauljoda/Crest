import SwiftUI

/// A form on iPhone and iPad already makes its rows as they scroll into view,
/// so each element stays one of the form's own rows.
struct CrestPlatformFormRows<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    // MARK: - Variables

    let data: Data
    let id: KeyPath<Data.Element, ID>
    let lazilyAbove: Int
    let row: (Data.Element) -> Row

    var body: some View {
        ForEach(data, id: id, content: row)
    }
}
