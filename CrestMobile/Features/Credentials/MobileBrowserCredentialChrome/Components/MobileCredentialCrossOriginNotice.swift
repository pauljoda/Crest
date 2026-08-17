import SwiftUI

struct MobileCredentialCrossOriginNotice: View {
    let message: LocalizedStringKey

    var body: some View {
        Label(
            message,
            systemImage: "rectangle.inset.filled.and.person.filled"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }
}
