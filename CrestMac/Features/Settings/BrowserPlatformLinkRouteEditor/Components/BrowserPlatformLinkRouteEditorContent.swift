import SwiftUI

struct BrowserPlatformLinkRouteEditorContent: View {
    let route: BrowserLinkRoute
    let spaces: [BrowserSpace]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: (BrowserLinkRouteFieldUpdate) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            HStack(spacing: CrestSpacing.small) {
                Toggle(
                    "Enabled",
                    isOn: binding(
                        route.isEnabled,
                        field: BrowserLinkRouteFieldUpdate.isEnabled
                    )
                )
                .labelsHidden()
                .help("Enable this route")

                Picker(
                    "Match",
                    selection: binding(
                        route.match,
                        field: BrowserLinkRouteFieldUpdate.match
                    )
                ) {
                    ForEach(BrowserLinkRouteMatch.allCases) { match in
                        Text(match.title).tag(match)
                    }
                }
                .labelsHidden()
                .frame(width: BrowserPlatformLinkRouteLayout.matchPickerWidth)

                TextField(
                    "URL or text",
                    text: binding(
                        route.pattern,
                        field: BrowserLinkRouteFieldUpdate.pattern
                    )
                )

                CrestSpaceMenuPicker(
                    "Destination",
                    selection: binding(
                        route.destinationSpaceID,
                        field: BrowserLinkRouteFieldUpdate.destinationSpaceID
                    ),
                    spaces: CrestSpaceIdentity.list(spaces),
                    labelsHidden: true
                )
                .frame(
                    width: BrowserPlatformLinkRouteLayout.destinationPickerWidth
                )

                Button("Move Up", systemImage: "chevron.up", action: moveUp)
                    .labelStyle(.iconOnly)
                    .disabled(!canMoveUp)
                Button("Move Down", systemImage: "chevron.down", action: moveDown)
                    .labelStyle(.iconOnly)
                    .disabled(!canMoveDown)
                Button(
                    "Delete Route",
                    systemImage: "trash",
                    role: .destructive,
                    action: delete
                )
                .labelStyle(.iconOnly)
            }

            Text("\(route.match.title) · opens in \(destinationName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var destinationName: String {
        spaces.first { $0.id == route.destinationSpaceID }?.name
            ?? "Missing Space"
    }

    private func binding<Value>(
        _ value: Value,
        field: @escaping (Value) -> BrowserLinkRouteFieldUpdate
    ) -> Binding<Value> {
        Binding {
            value
        } set: { value in
            update(field(value))
        }
    }
}
