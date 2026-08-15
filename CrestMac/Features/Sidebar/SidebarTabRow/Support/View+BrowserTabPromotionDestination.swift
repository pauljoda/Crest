import SwiftUI

extension View {
    @ViewBuilder
    func browserTabPromotionDestination(
        id: String,
        in namespace: Namespace.ID?
    ) -> some View {
        if let namespace {
            matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: false
            )
        } else {
            self
        }
    }
}
