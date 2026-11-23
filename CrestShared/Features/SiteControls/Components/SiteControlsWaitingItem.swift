import SwiftUI

/// What waits on the person, under the actions: a permission request with
/// Deny and Allow, a blocked pop-up with Allow, or Developer Mode with Turn
/// Off. It is there only while something waits, on the same surface as the
/// tiles around it.
struct SiteControlsWaitingItem: View {
    // MARK: - Types

    /// One item, whatever waits: its words and its buttons.
    @MainActor
    struct Content {
        let symbol: String
        let title: Text
        let detail: Text
        var deny: Button?
        var primary: Button?
        /// The waiting permission request, whose item also chooses whether
        /// the answer is remembered in the Space.
        var request: BrowserPagePermissionController.Request?
        let identifier: String

        /// A button the item offers.
        struct Button {
            let title: LocalizedStringResource
            /// Whether the button is the one Crest blue marks, as Allow is.
            var isPrimary = true
            let accessibilityLabel: Text
            var accessibilityHint: Text?
            var identifier: String?
            let action: @MainActor () -> Void
        }

        /// What waits on the person for `model`'s page, the most urgent
        /// first, or nil while nothing does.
        init?(model: SiteControlsModel) {
            if let request = model.page.sitePermissionRequests.current {
                self.init(permission: request, model: model)
            } else if let notice = model.page.blockedPopupNotice {
                self.init(popup: notice, model: model)
            } else if let developerMode = model.platform.developerMode {
                self.init(developerMode: developerMode)
            } else {
                return nil
            }
        }

        private init(permission request: BrowserPagePermissionController.Request, model: SiteControlsModel) {
            let site = request.origin.displayName
            let permission = String(localized: request.permission.title)
            symbol = request.permission.symbol
            title = Text(request.permission.question)
            detail =
                request.origin == request.topLevelOrigin
                ? Text(verbatim: site) : Text("\(site), inside \(request.topLevelOrigin.displayName)")
            deny = Button(
                title: "Deny", isPrimary: false, accessibilityLabel: Text("Deny \(site) \(permission)"),
                identifier: "site-permission-deny"
            ) { model.answer(request, allows: false) }
            primary = Button(
                title: "Allow", accessibilityLabel: Text("Allow \(site) \(permission)"),
                identifier: "site-permission-allow"
            ) { model.answer(request, allows: true) }
            self.request = request
            identifier = "site-permission-request"
        }

        private init(popup notice: BrowserBlockedPopupNotice, model: SiteControlsModel) {
            symbol = notice.status.offersAllow ? "macwindow.on.rectangle" : "checkmark.circle"
            title = notice.status.offersAllow ? Text("Pop-up blocked") : Text("Pop-ups allowed")
            detail =
                notice.status.offersAllow ? Text(verbatim: notice.origin.host) : Text("Retry the action on the page.")
            if notice.status.offersAllow {
                primary = Button(
                    title: "Allow", accessibilityLabel: Text(notice.allowActionAccessibilityLabel),
                    accessibilityHint: Text(notice.allowActionAccessibilityHint),
                    identifier: "allow-blocked-automatic-popups"
                ) { model.page.allowAutomaticPopupsForBlockedSite(shownFor: notice.origin) }
            }
            identifier = "blocked-popup-site-control-notice"
        }

        private init(developerMode: SiteControlsDeveloperMode) {
            symbol = "hammer"
            title = Text("Developer Mode is on")
            detail =
                developerMode.isAutomatic ? Text("On by itself for this address") : Text("The developer toolbar shows")
            primary = Button(
                title: "Turn Off", isPrimary: false, accessibilityLabel: Text("Turn Off Developer Mode"),
                identifier: "site-developer-mode-off", action: developerMode.turnOff)
            identifier = "site-developer-mode"
        }
    }

    // MARK: - Variables

    let model: SiteControlsModel
    let content: Content

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: CrestSpacing.small + 1) {
                Image(systemName: content.symbol)
                    .font(.system(size: metrics.glyphSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.glyphSize + 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    content.title
                        .font(metrics.rowFont.weight(.semibold))
                        .lineLimit(1)
                    content.detail
                        .font(metrics.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let deny = content.deny {
                    button(deny)
                }
                if let primary = content.primary {
                    button(primary)
                }
            }
            if let request = content.request {
                Toggle(isOn: Bindable(model).remembersPermission) {
                    Text("Remember in \(request.spaceName)")
                        .font(metrics.detailFont)
                }
                #if os(macOS)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                #endif
                .padding(.leading, metrics.glyphSize + 4 + CrestSpacing.small + 1)
                .accessibilityIdentifier("site-permission-remember")
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, 10)
        .padding(.trailing, CrestSpacing.small)
        .frame(minHeight: metrics.waitingHeight)
        .background(CrestColor.chromeSurface, in: .rect(cornerRadius: CrestRadius.control))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(content.identifier)
    }

    private func button(_ button: Content.Button) -> some View {
        Button(String(localized: button.title), action: button.action)
            .buttonStyle(button.isPrimary ? CrestButtonStyle.crestPrimary : CrestButtonStyle.crestSecondary)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel(button.accessibilityLabel)
            .accessibilityHint(button.accessibilityHint ?? Text(verbatim: ""))
            .accessibilityIdentifier(button.identifier ?? "")
    }
}
