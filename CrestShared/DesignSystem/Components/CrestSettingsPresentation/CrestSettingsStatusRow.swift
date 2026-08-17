import SwiftUI

struct CrestSettingsStatusRow<Status: View>: View {
    let title: LocalizedStringResource
    private let status: Status

    init(
        _ title: LocalizedStringResource,
        @ViewBuilder status: () -> Status
    ) {
        self.title = title
        self.status = status()
    }

    var body: some View {
        HStack(
            alignment: .center,
            spacing: CrestSettingsPresentationMetrics.statusSpacing
        ) {
            Text(title)
            Spacer(minLength: 0)
            status
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
