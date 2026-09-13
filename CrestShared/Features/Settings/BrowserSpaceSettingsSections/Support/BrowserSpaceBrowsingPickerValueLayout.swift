import SwiftUI

struct BrowserSpaceBrowsingPickerValueLayout: Equatable {
    let minimumLeadingGap: CGFloat
    let providerTextSpacing: CGFloat
    let disclosureSpacing: CGFloat
    let verticalPadding: CGFloat
    let providerTitleLineLimit: Int
    let minimumProviderTitleScale: CGFloat

    static let touch = Self(
        minimumLeadingGap: 16,
        providerTextSpacing: 10,
        disclosureSpacing: 8,
        verticalPadding: 5,
        providerTitleLineLimit: 1,
        minimumProviderTitleScale: 0.8
    )
}
