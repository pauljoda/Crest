import SwiftUI

struct BrowserLinkSettingsContent: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @Bindable var links: BrowserLinkPreferenceStore

    var body: some View {
        BrowserExternalLinkDestinationSection(
            destination: externalDestinationBinding,
            spaceID: externalSpaceBinding,
            spaces: availableSpaces
        )

        BrowserQuickWindowSettingsSection(
            archivePolicy: archivePolicyBinding,
            remembersSpaceBySite: rememberSpaceBinding
        )

        BrowserPeekSettingsSection(
            automaticallyOpensPeek: automaticPeekBinding,
            clickModifier: peekClickModifierBinding
        )

        if lockedRouteDestinationSpaces.isEmpty {
            BrowserLinkRoutingSection(
                routes: links.preferences.routes,
                spaces: availableSpaces,
                selectedSpaceID: resolvedSelectedSpaceID,
                updateRoute: updateRoute,
                remove: links.removeRoute,
                move: links.moveRoute,
                add: links.addRoute
            )
        } else {
            Section("Routing") {
                Text("Unlock the private Spaces below before viewing or changing URL route patterns that target them.")
                    .crestFormFootnote()

                ForEach(lockedRouteDestinationSpaces) { space in
                    BrowserSettingsPrivateSpaceAccessRow(
                        space: space,
                        accessController: spaceAccess
                    )
                }
            }
            .accessibilityIdentifier("settings-private-link-routes")
        }
    }

    private var availableSpaces: [BrowserSpace] {
        browser.session.spaces.filter {
            !browser.deletingSpaceIDs.contains($0.id)
        }
    }

    private var resolvedSelectedSpaceID: SpaceID {
        BrowserLinkSettingsSpacePolicy.resolvedExternalSpaceID(
            preferredSpaceID: browser.session.selectedSpaceID,
            spaces: browser.session.spaces,
            selectedSpaceID: browser.session.selectedSpaceID,
            unavailableSpaceIDs: browser.deletingSpaceIDs
        )
    }

    private var lockedRouteDestinationSpaces: [BrowserSpace] {
        BrowserSettingsPrivacyPolicy.lockedRouteDestinationSpaces(
            for: links.preferences.routes,
            in: browser.session.spaces,
            accessController: spaceAccess
        )
    }

    private var externalDestinationBinding: Binding<BrowserExternalLinkDestination> {
        Binding {
            links.preferences.externalLinkDestination
        } set: { value in
            links.update { $0.externalLinkDestination = value }
        }
    }

    private var archivePolicyBinding: Binding<BrowserQuickWindowArchivePolicy> {
        Binding {
            links.preferences.quickWindowArchivePolicy
        } set: { value in
            links.update { $0.quickWindowArchivePolicy = value }
        }
    }

    private var externalSpaceBinding: Binding<SpaceID?> {
        Binding {
            BrowserLinkSettingsSpacePolicy.resolvedExternalSpaceID(
                preferredSpaceID: links.preferences.externalLinkSpaceID,
                spaces: browser.session.spaces,
                selectedSpaceID: browser.session.selectedSpaceID,
                unavailableSpaceIDs: browser.deletingSpaceIDs
            )
        } set: { value in
            links.update { $0.externalLinkSpaceID = value }
        }
    }

    private var rememberSpaceBinding: Binding<Bool> {
        Binding {
            links.preferences.remembersQuickWindowSpaceBySite
        } set: { value in
            links.update { $0.remembersQuickWindowSpaceBySite = value }
        }
    }

    private var automaticPeekBinding: Binding<Bool> {
        Binding {
            links.preferences.automaticallyOpensPeek
        } set: { value in
            links.update { $0.automaticallyOpensPeek = value }
        }
    }

    private var peekClickModifierBinding: Binding<BrowserLinkClickModifier> {
        Binding {
            links.preferences.peekClickModifier
        } set: { value in
            links.update { $0.peekClickModifier = value }
        }
    }

    private func updateRoute(
        _ routeID: UUID,
        _ field: BrowserLinkRouteFieldUpdate
    ) {
        links.updateRoute(routeID, field: field)
    }
}

#Preview("Link Settings Content") {
    let fixture = BrowserLinkSettingsPreviewFixture()
    Form {
        BrowserLinkSettingsContent(
            browser: fixture.browser,
            spaceAccess: fixture.spaceAccess,
            links: fixture.links
        )
    }
    .formStyle(.grouped)
}
