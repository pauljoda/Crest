import SwiftUI

/// A route reads as a condition followed by its destination, in the form row
/// that holds it. The pattern always gets a usable editing width; narrow
/// containers stack the destination below it.
struct BrowserLinkRouteCard: View {
    // MARK: - Static Variables

    static let patternMinimumWidth: CGFloat = 200
    static let destinationWidth: CGFloat = 220
    static let destinationMinimumHeight: CGFloat = 36

    // MARK: - Variables

    let route: LinkRoute
    let spaces: [SpaceModel]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: (BrowserLinkRouteFieldUpdate) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    @FocusState private var isPatternFocused: Bool

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CrestSpacing.medium) {
                    condition
                    Spacer(minLength: CrestSpacing.medium)
                    actions
                }
                VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                    condition
                    actions
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: CrestSpacing.extraLarge) {
                    pattern.frame(minWidth: Self.patternMinimumWidth)
                    destination.frame(width: Self.destinationWidth)
                }
                VStack(alignment: .leading, spacing: CrestSpacing.large) {
                    pattern
                    destination
                }
            }
        }
        .padding(.vertical, CrestSpacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link-route-\(route.id.uuidString.lowercased())")
    }

    private var condition: some View {
        HStack(spacing: CrestSpacing.small) {
            Text("When URL").fontWeight(.medium)
            Picker("Match", selection: binding(route.match, field: BrowserLinkRouteFieldUpdate.match)) {
                ForEach(LinkRouteMatch.all, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
    }

    private var actions: some View {
        HStack(spacing: CrestSpacing.medium) {
            Toggle("Enabled", isOn: binding(route.isEnabled, field: BrowserLinkRouteFieldUpdate.isEnabled))
                .toggleStyle(.switch).fixedSize()
            Menu {
                Group {
                    Button("Move Up", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                    Button("Move Down", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                    Divider()
                    Button("Delete Route", systemImage: "trash", role: .destructive, action: delete)
                }
                .crestMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(CrestChromeButtonStyle())
            .menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Route actions")
        }
    }

    private var pattern: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("URL or text").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: CrestSpacing.small) {
                Image(systemName: "link").foregroundStyle(.secondary)
                // A grouped form shows a field's title as a row label beside
                // it, so the example is a prompt and the label stays hidden.
                TextField(
                    "URL or text", text: binding(route.pattern, field: BrowserLinkRouteFieldUpdate.pattern),
                    prompt: Text("example.com")
                )
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($isPatternFocused)
                .autocorrectionDisabled()
                #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
            }
            .crestFieldSurface(isFocused: isPatternFocused)
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("Open in Space").font(.caption).foregroundStyle(.secondary)
            CrestSpaceMenuPicker(
                "Destination",
                selection: binding(route.destinationSpaceID, field: BrowserLinkRouteFieldUpdate.destinationSpaceID),
                spaces: CrestSpaceIdentity.list(spaces), labelsHidden: true
            )
            .frame(maxWidth: .infinity, minHeight: Self.destinationMinimumHeight, alignment: .leading)
        }
    }

    // MARK: - Actions - Bindings

    private func binding<Value>(_ value: Value, field: @escaping (Value) -> BrowserLinkRouteFieldUpdate) -> Binding<
        Value
    > {
        Binding(get: { value }, set: { update(field($0)) })
    }
}
