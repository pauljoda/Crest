import SwiftUI

struct MobileSidebarAddressField: View {
    let browser: BrowserStore
    let pageActions: (any MobilePageActions)?
    @Binding var text: String
    @Binding var isEditing: Bool
    let isSecure: Bool
    let progress: Double
    let isLoading: Bool
    let activate: () -> Void
    let submit: () -> Void
    let morphNamespace: Namespace.ID
    let morphID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            if let pageActions, pageActions.isAvailable, !isEditing {
                MobilePageActionsMenu(
                    browser: browser,
                    pages: pageActions,
                    systemImage: "ellipsis.circle"
                )
                .frame(width: 44, height: 44)
            } else {
                Image(
                    systemName: isEditing
                        ? (isSecure ? "lock.fill" : "magnifyingglass")
                        : "ellipsis.circle"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }

            BrowserAddressContent(
                text: $text,
                isEditing: $isEditing,
                activate: activate,
                submit: submit
            )

            if isEditing, !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: CrestLayout.sidebarRowHeight)
        .background {
            ZStack(alignment: .leading) {
                fieldShape.fill(CrestColor.chromeSurface)
                fieldShape
                    .fill(.tint.opacity(isLoading ? 0.2 : 0))
                    .scaleEffect(x: loadingProgress, anchor: .leading)
                    .mask(fieldShape)
                    .animation(
                        BrowserVisualAccessibilityPolicy.animation(
                            CrestMotion.loadingProgress,
                            reduceMotion: reduceMotion
                        ),
                        value: loadingProgress
                    )
            }
        }
        .matchedGeometryEffect(
            id: morphID,
            in: morphNamespace,
            properties: .frame,
            anchor: .center,
            isSource: true
        )
        .overlay {
            fieldShape
                .strokeBorder(Color.accentColor.opacity(isEditing ? 0.7 : 0), lineWidth: 1)
        }
        .contextMenu {
            if let pageActions, pageActions.isAvailable, !isEditing {
                MobilePageActionsContent(browser: browser, pages: pageActions)
                    .tint(.primary)
            }
        }
    }

    private var loadingProgress: CGFloat {
        isLoading ? CGFloat(min(max(progress, 0.04), 1)) : 0
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CrestLayout.sidebarControlCornerRadius,
            style: .continuous
        )
    }
}

#Preview("Sidebar Address Field") {
    @Previewable @Namespace var morphNamespace
    @Previewable @State var text = "example.com"
    @Previewable @State var isEditing = false
    let fixture = MobilePageActionsPreviewFixture()

    MobileSidebarAddressField(
        browser: fixture.browser,
        pageActions: fixture.actions,
        text: $text,
        isEditing: $isEditing,
        isSecure: true,
        progress: 0.4,
        isLoading: true,
        activate: {},
        submit: {},
        morphNamespace: morphNamespace,
        morphID: "preview-address-field"
    )
    .padding()
    .frame(width: 390)
}
