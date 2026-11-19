import SwiftUI

/// Whether Crest is the default browser, and the platform's way to make it
/// so, checked again on request. General settings and setup's last step both
/// show it, setup under its page's heading.
struct BrowserDefaultBrowserSection<Header: View>: View {
    // MARK: - Variables

    private let header: Header
    @State private var defaultBrowser = BrowserDefaultBrowserController()
    @State private var isCheckingDefaultBrowser = true

    // MARK: - Initializers

    init(@ViewBuilder header: () -> Header) {
        self.header = header()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Section {
            // The Mac keeps the status and its action on one line; a phone's
            // row is too narrow, so the action takes a row of its own there.
            #if os(macOS)
                LabeledContent("Default browser") {
                    HStack(spacing: CrestSpacing.small) {
                        status
                        actions
                        checkAgainButton
                    }
                }
            #else
                HStack(spacing: CrestSpacing.small) {
                    Text("Default browser")
                    Spacer(minLength: CrestSpacing.small)
                    status
                    checkAgainButton
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                actions
            #endif
        } header: {
            header
        } footer: {
            if let message = defaultBrowser.status.message {
                Text(message).crestFormFootnote()
            }
        }
        .task {
            guard defaultBrowser.status == .unknown else {
                isCheckingDefaultBrowser = false
                return
            }
            await refreshStatus()
        }
    }

    @ViewBuilder
    private var status: some View {
        if isCheckingDefaultBrowser {
            HStack(spacing: CrestSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Checking…")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("default-browser-status")
        } else {
            Label(
                defaultBrowser.status.title,
                systemImage: defaultBrowser.status.symbol
            )
            .foregroundStyle(statusStyle)
            .accessibilityIdentifier("default-browser-status")
        }
    }

    private var checkAgainButton: some View {
        Button {
            Task { await refreshStatus() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help("Check Again")
        .accessibilityLabel("Check Again")
        .disabled(isCheckingDefaultBrowser || defaultBrowser.isWorking)
        .accessibilityIdentifier("check-default-browser-status")
    }

    @ViewBuilder
    private var actions: some View {
        if defaultBrowser.status != .isDefault {
            let style = defaultBrowser.requestStyle
            Button(style.buttonTitle) {
                style.request(defaultBrowser)
            }
            .disabled(style.waitsForRequest && defaultBrowser.isWorking)
            .accessibilityIdentifier(style.buttonIdentifier)
        }
    }

    private var statusStyle: AnyShapeStyle {
        switch defaultBrowser.status.tone {
        case .quiet: AnyShapeStyle(.secondary)
        case .success: AnyShapeStyle(CrestColor.success)
        case .warning: AnyShapeStyle(CrestColor.warning)
        }
    }

    // MARK: - Mutators

    @MainActor
    private func refreshStatus() async {
        isCheckingDefaultBrowser = true
        defer { isCheckingDefaultBrowser = false }
        await Task.yield()
        guard !Task.isCancelled else { return }
        defaultBrowser.refreshStatus()
    }
}

extension BrowserDefaultBrowserSection where Header == EmptyView {
    init() {
        self.init { EmptyView() }
    }
}
