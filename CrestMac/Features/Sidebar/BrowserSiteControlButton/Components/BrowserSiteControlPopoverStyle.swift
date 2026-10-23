import SwiftUI

/// Site controls draw in their Space's appearance: the color scheme its text
/// color gives the sidebar, with the device's surface material and the labels
/// in that same scheme. The popover sets its own foreground because the
/// sidebar's Space foreground would otherwise carry into it, and draws its own
/// surface so the material can never disagree with the labels above it.
struct BrowserSiteControlPopoverStyle: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(.primary)
            .tint(CrestBrandTheme.accent(colorScheme))
            .presentationBackground {
                CrestSurfaceLayer(shape: Rectangle())
                    .environment(\.colorScheme, colorScheme)
            }
            .preferredColorScheme(colorScheme)
            .environment(\.colorScheme, colorScheme)
    }
}

#if DEBUG
    #Preview("Popover from a dark-ink Space") {
        BrowserSiteControlStylePreview(colorScheme: .light)
            .foregroundStyle(Color.white)
            .environment(\.colorScheme, .dark)
    }

    #Preview("Popover from a light-ink Space") {
        BrowserSiteControlStylePreview(colorScheme: .dark)
            .foregroundStyle(Color.black)
            .tint(.black)
            .environment(\.colorScheme, .light)
    }

    private struct BrowserSiteControlStylePreview: View {
        let colorScheme: ColorScheme
        @State private var remembersChoice = true

        var body: some View {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                Text("Site Controls").font(.headline)
                Text(verbatim: "example.com").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: CrestSpacing.small) {
                    BrowserSiteQuickActionButton(title: "Copy Link", systemImage: "square.and.arrow.up", action: {})
                    BrowserSiteQuickActionButton(title: "Reload", systemImage: "arrow.clockwise", action: {})
                    BrowserSiteQuickActionButton(title: "Capture", systemImage: "camera", action: {}).disabled(true)
                }
                Divider()
                Label("Secure", systemImage: "lock.fill").foregroundStyle(.green)
                Text("Permissions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Label("Camera", systemImage: "video").font(.caption)
                    Spacer()
                    Menu("Ask") {
                        Button("Allow") {}
                        Button("Block") {}
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Toggle("Remember in this Space", isOn: $remembersChoice).toggleStyle(.checkbox).font(.caption)
                HStack {
                    Button("Deny") {}.buttonStyle(.bordered)
                    Button("Allow") {}.buttonStyle(.borderedProminent)
                }
            }
            .padding(CrestSpacing.medium)
            .frame(width: BrowserSiteControlMetrics.width)
            .modifier(BrowserSiteControlPopoverStyle(colorScheme: colorScheme))
            .background { CrestSurfaceLayer(shape: Rectangle()).environment(\.colorScheme, colorScheme) }
            .padding()
            .background(.indigo.gradient)
        }
    }
#endif
