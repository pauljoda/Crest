import SwiftUI

struct MobileBrowserFindBar: View {
    let page: MobileBrowserPage

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var query = ""
    @FocusState private var queryIsFocused: Bool

    var body: some View {
        HStack(spacing: MobileBrowserChromeLayout.findItemSpacing) {
            TextField("Find in Page", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($queryIsFocused)
                .onSubmit {
                    page.find(query, direction: .forward)
                }
                .accessibilityIdentifier("find-field")

            MobileBrowserFindStatus(state: page.findMatchState)

            findButton(
                title: "Previous Match",
                systemImage: "chevron.up",
                enabled: !query.isEmpty
            ) {
                page.find(query, direction: .backward)
            }

            findButton(
                title: "Next Match",
                systemImage: "chevron.down",
                enabled: !query.isEmpty
            ) {
                page.find(query, direction: .forward)
            }

            findButton(title: "Close Find", systemImage: "xmark") {
                page.dismissFind()
            }
        }
        .padding(.leading, MobileBrowserChromeLayout.findLeadingPadding)
        .padding(.trailing, MobileBrowserChromeLayout.findTrailingPadding)
        .frame(minHeight: CrestLayout.minimumHitTarget)
        .glassEffect(.regular, in: .capsule)
        .shadow(
            color: .black.opacity(
                reduceTransparency ? 0 : MobileBrowserChromeLayout.findShadowOpacity
            ),
            radius: MobileBrowserChromeLayout.findShadowRadius,
            y: MobileBrowserChromeLayout.findShadowOffset
        )
        .onAppear { queryIsFocused = true }
        .onChange(of: query) {
            page.find(query, direction: .forward)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("find-bar")
    }

    private func findButton(
        title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(
                width: MobileBrowserChromeLayout.findButtonWidth,
                height: CrestLayout.minimumHitTarget
            )
            .contentShape(.rect)
            .disabled(!enabled)
    }
}

#Preview("Mobile Browser — Find Bar", traits: .fixedLayout(width: 390, height: 88)) {
    MobileBrowserFindBar(page: MobileBrowserPagePreviewFixture.makePage())
        .padding()
}
