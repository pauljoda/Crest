import SwiftUI

struct SidebarTabTrailingControl: View {
    let configuration: SidebarTabRowConfiguration
    let isHovering: Bool

    @ViewBuilder
    var body: some View {
        if configuration.tab.placement == .saved,
            let unload = configuration.unload
        {
            SidebarTabUnloadButton(
                configuration: configuration,
                unload: unload,
                isVisible: configuration.isLoaded
                    && (isHovering || configuration.isSelected)
            )
        } else {
            SidebarTabCloseButton(
                configuration: configuration,
                isVisible: configuration.canClose
                    && (isHovering || configuration.isSelected)
            )
        }
    }
}

#Preview {
    SidebarTabTrailingControl(
        configuration: SidebarTabRowPreviewFixture.configuration(),
        isHovering: true
    )
    .padding()
}
