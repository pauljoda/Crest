import SwiftUI

/// A grouped form on the Mac makes every row it holds, and each button or menu
/// in a row brings its own AppKit views, which the window walks on every frame
/// a form scrolls. A section of hundreds of rows made the whole page stutter, so
/// past `lazilyAbove` these rows sit in one row of the form and are made as they
/// scroll into view, spaced and divided as the form spaces and divides its own
/// rows.
struct CrestPlatformFormRows<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    // MARK: - Static Variables

    /// The room a grouped form keeps above and below each row's content.
    private static var rowInset: CGFloat { 10 }

    // MARK: - Variables

    let data: Data
    let id: KeyPath<Data.Element, ID>
    let lazilyAbove: Int
    let row: (Data.Element) -> Row

    var body: some View {
        if data.count <= lazilyAbove {
            ForEach(data, id: id, content: row)
        } else if let first = data.first?[keyPath: id] {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(data, id: id) { element in
                    VStack(spacing: 0) {
                        if element[keyPath: id] != first {
                            Divider()
                        }
                        row(element)
                            .padding(.vertical, Self.rowInset)
                    }
                }
            }
            // Each row brings the form's room itself, so the form's own room
            // around this one row is taken back.
            .padding(.vertical, -Self.rowInset)
        }
    }
}
