import SwiftUI

struct BrowserFindBar: View {
    let page: BrowserPage

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var query = ""
    @FocusState private var focusedField: BrowserFindBarField?

    var body: some View {
        HStack(spacing: BrowserFindBarMetrics.controlSpacing) {
            TextField("Find in Page", text: $query)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .query)
                .frame(width: BrowserFindBarMetrics.queryWidth)
                .onSubmit {
                    page.find(query, direction: .forward)
                }

            if let label = page.findMatchState.accessibilityLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(
                        page.findMatchState == .notFound ? .red : .secondary
                    )
                    .frame(
                        minWidth: BrowserFindBarMetrics.resultMinimumWidth,
                        alignment: .trailing
                    )
                    .accessibilityIdentifier("find-result")
            }

            Button("Previous Match", systemImage: "chevron.up") {
                page.find(query, direction: .backward)
            }
            .disabled(query.isEmpty)

            Button("Next Match", systemImage: "chevron.down") {
                page.find(query, direction: .forward)
            }
            .disabled(query.isEmpty)

            Button("Close Find", systemImage: "xmark", action: page.dismissFind)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, BrowserFindBarMetrics.horizontalPadding)
        .frame(height: BrowserFindBarMetrics.height)
        .background(
            .background,
            in: .rect(cornerRadius: BrowserFindBarMetrics.cornerRadius)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: BrowserFindBarMetrics.cornerRadius,
                style: .continuous
            )
            .strokeBorder(.separator, lineWidth: BrowserFindBarMetrics.strokeWidth)
        }
        .shadow(
            color: .black.opacity(
                reduceTransparency ? 0 : BrowserFindBarMetrics.shadowOpacity
            ),
            radius: BrowserFindBarMetrics.shadowRadius,
            y: BrowserFindBarMetrics.shadowY
        )
        .defaultFocus($focusedField, .query)
        .onChange(of: query) {
            page.find(query, direction: .forward)
        }
        .onExitCommand(perform: page.dismissFind)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("find-bar")
    }
}
