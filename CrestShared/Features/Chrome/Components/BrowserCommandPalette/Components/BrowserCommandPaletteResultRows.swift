import SwiftUI

struct BrowserCommandPaletteResultRows: View {
    let model: BrowserCommandPaletteModel
    let group: BrowserCommandPaletteGroup
    /// The rows run from the bottom, the first nearest the field below.
    var listsUpward = false

    var body: some View {
        ForEach(listsUpward ? group.items.reversed() : group.items) { item in
            if item.row.kind.isPrimary || group.section == .topHit {
                BrowserCommandPaletteIntentRow(model: model, item: item)
                    .id(item.id)
            } else {
                BrowserCommandPaletteResultRow(model: model, item: item, namesKind: group.section == .results)
                    .id(item.id)
            }
        }
    }
}
