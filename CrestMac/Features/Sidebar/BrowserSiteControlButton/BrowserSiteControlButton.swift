import SwiftUI

struct BrowserSiteControlButton: View {
    let configuration: BrowserSiteControlConfiguration

    @State private var isPresented = false

    var body: some View {
        BrowserSiteControlTrigger(
            isPresented: presentationBinding,
            blockedPopupNotice: configuration.page.blockedPopupState.notice
        )
        .popover(isPresented: presentationBinding, arrowEdge: .top) {
            BrowserSiteControlPopover(
                configuration: configuration,
                dismiss: { presentationBinding.wrappedValue = false }
            )
            // Bright page content must not wash out the popover's light labels.
            .presentationBackground(Color(white: 0.12))
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
        }
        .onDisappear {
            guard isPresented else { return }
            presentationBinding.wrappedValue = false
        }
    }

    private var presentationBinding: Binding<Bool> {
        Binding {
            isPresented
        } set: { isPresented in
            guard isPresented != self.isPresented else { return }
            self.isPresented = isPresented
            configuration.presentationChanged(isPresented)
        }
    }
}
