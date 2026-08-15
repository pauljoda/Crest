import SwiftUI

extension View {
    @ViewBuilder
    func browserPinnedTabPromotionDestination(
        id: String,
        in namespace: Namespace.ID?,
        usesNativeNavigationTransition: Bool,
        isTransitionSource: Bool
    ) -> some View {
        if let namespace, usesNativeNavigationTransition, isTransitionSource {
            matchedTransitionSource(id: id, in: namespace)
        } else if let namespace, !usesNativeNavigationTransition {
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
