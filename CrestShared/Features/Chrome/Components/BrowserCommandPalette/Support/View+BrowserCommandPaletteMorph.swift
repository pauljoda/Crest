import SwiftUI

extension View {
    @ViewBuilder
    func browserPaletteMorph(
        id: String?,
        in namespace: Namespace.ID?,
        reduceMotion: Bool
    ) -> some View {
        if reduceMotion || id == nil || namespace == nil {
            self
        } else if let id, let namespace {
            matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: false
            )
        }
    }
}
