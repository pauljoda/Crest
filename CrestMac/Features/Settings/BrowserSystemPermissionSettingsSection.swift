import AppKit
import SwiftUI

struct BrowserSystemPermissionSettingsSection: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @Environment(BrowserPasskeyAccessController.self) private var passkeyAccess

    var body: some View {
        BrowserSystemPermissionSettingsContent(
            browser: browser, spaceAccess: spaceAccess,
            service: BrowserSystemPermissionService(core: browser.core, passkeyAccess: passkeyAccess))
    }
}

/// The permission rows over one permission service. The service is made once,
/// when the section first appears.
private struct BrowserSystemPermissionSettingsContent: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @State private var controller: BrowserSystemPermissionController

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, service: BrowserSystemPermissionService) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        _controller = State(initialValue: BrowserSystemPermissionController(service: service))
    }

    private var spaceID: SpaceID? {
        guard BrowserSettingsPrivacyPolicy.canRevealSpaceData(in: browser.selectedSpace, accessController: spaceAccess)
        else { return nil }
        return browser.selectedSpace?.id
    }

    var body: some View {
        Section("System Permissions", systemImage: "hand.raised") {
            VStack(spacing: 0) {
                ForEach(BrowserSystemPermission.all) { permission in
                    BrowserSystemPermissionRow(
                        permission: permission,
                        status: controller.status(for: permission),
                        error: controller.errors[permission],
                        isWorking: controller.working.contains(permission),
                        spaceName: spaceID == nil ? nil : browser.selectedSpace?.name,
                        request: { Task { await controller.request(permission, spaceID: spaceID) } },
                        openSettings: { controller.openSettings(for: permission) },
                        chooseFolder: {
                            guard let spaceID else { return }
                            Task { await controller.chooseFolder(spaceID: spaceID) }
                        }
                    )
                    if permission != BrowserSystemPermission.all.last {
                        Divider().padding(.vertical, 12)
                    }
                }
            }
        }
        .containerValue(\.settingsFullWidth, true)
        .task(id: spaceID) { await controller.refresh(spaceID: spaceID) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh(spaceID: spaceID, recheckFiles: true) }
        }
    }
}
