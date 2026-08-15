import SwiftUI

struct MobileSpacePicker: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollAnchorSpaceID: SpaceID?

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    let width = pickerWidth(for: geometry.size.width)

                    ZStack {
                        Picker("Spaces", selection: selection) {
                            ForEach(spaces) { space in
                                MobileSpacePickerSegment(
                                    space: space,
                                    browser: browser,
                                    pages: pages,
                                    spaceAccess: spaceAccess,
                                    selectSpace: selectSpace
                                )
                                .tag(space.id)
                                .accessibilityLabel(space.name)
                                .accessibilityValue(
                                    space.accessPolicy.requiresAuthentication
                                        ? "Private Space"
                                        : "Open Space"
                                )
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.extraLarge)
                        .labelsHidden()

                        pickerScrollAnchors(width: width)
                    }
                    .frame(width: width, height: 52)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard
                                let destination = scrollDestination(
                                    for: value.translation.width
                                )
                            else { return }
                            scrollAnchorSpaceID = destination
                            withAnimation(
                                BrowserVisualAccessibilityPolicy.animation(
                                    CrestMotion.scrollAlignment,
                                    reduceMotion: reduceMotion
                                )
                            ) {
                                reader.scrollTo(destination, anchor: .center)
                            }
                        }
                )
                .accessibilityLabel("Spaces")
                .accessibilityIdentifier("space-switcher-picker")
                .task(id: browser.session.selectedSpaceID) {
                    await Task.yield()
                    scrollAnchorSpaceID = browser.session.selectedSpaceID
                    withAnimation(
                        BrowserVisualAccessibilityPolicy.animation(
                            CrestMotion.scrollAlignment,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        reader.scrollTo(browser.session.selectedSpaceID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 52)
    }

    private var selection: Binding<SpaceID> {
        Binding(
            get: { browser.session.selectedSpaceID },
            set: { spaceID in
                selectSpace(spaceID)
            }
        )
    }

    private func pickerWidth(for availableWidth: CGFloat) -> CGFloat {
        max(availableWidth, CGFloat(spaces.count) * 52)
    }

    private func pickerScrollAnchors(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                Color.clear
                    .frame(
                        width: width / CGFloat(max(spaces.count, 1))
                    )
                    .id(space.id)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scrollDestination(for translation: CGFloat) -> SpaceID? {
        guard !spaces.isEmpty,
            abs(translation) >= 12,
            let currentIndex = spaces.firstIndex(where: {
                $0.id == (scrollAnchorSpaceID ?? browser.session.selectedSpaceID)
            })
        else { return nil }

        let semanticTranslation = BrowserChromeDirectionPolicy.semanticHorizontalTranslation(
            translation,
            layoutDirection: layoutDirection
        )
        let stepCount = max(1, Int(ceil(abs(translation) / 52)))
        let requestedIndex =
            semanticTranslation < 0
            ? currentIndex + stepCount
            : currentIndex - stepCount
        let destinationIndex = min(max(requestedIndex, spaces.startIndex), spaces.index(before: spaces.endIndex))
        return spaces[destinationIndex].id
    }

    private var spaces: [BrowserSpace] {
        BrowserSidebarAccessPolicy.availableSpaces(in: browser)
    }
}

#Preview("Mobile Space Picker", traits: .sizeThatFitsLayout) {
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileSpacePicker(
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        selectSpace: { _ in }
    )
    .frame(width: 390)
    .padding()
}
