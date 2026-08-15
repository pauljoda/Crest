import SwiftUI

extension View {
    @ViewBuilder
    func mobileTabTransitionSource(
        id: String,
        in namespace: Namespace.ID?,
        usesNativeNavigationTransition: Bool,
        isEnabled: Bool
    ) -> some View {
        if let namespace, isEnabled {
            if usesNativeNavigationTransition {
                matchedTransitionSource(id: id, in: namespace)
            } else {
                matchedGeometryEffect(
                    id: id,
                    in: namespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: false
                )
            }
        } else {
            self
        }
    }
}
