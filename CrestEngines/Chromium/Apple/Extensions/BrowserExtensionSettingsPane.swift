import SwiftUI

struct BrowserExtensionSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var requestedSpaceID: SpaceID?
    var requestRevision = 0
    @State private var selectedSpaceID: SpaceID?
    private var store: ChromiumExtensionStore { CrestChromiumRoot.extensions }
    private var space: BrowserSpace? { browser.session.space(id: selectedSpaceID ?? browser.selectedSpaceID) }

    var body: some View {
        BrowserSettingsPane(.extensions) {
            Section("Space", systemImage: "square.grid.2x2") {
                CrestSpaceMenuPicker("Manage extensions for", selection: $selectedSpaceID,
                    spaces: CrestSpaceIdentity.list(browser.session.spaces))
            }
            if let space, !spaceAccess.isLocked(space) {
                BrowserExtensionsView(space: space, store: store).id(space.profile.id)
            } else if let space {
                BrowserSettingsPrivateSpaceAccessSection(space: space, accessController: spaceAccess,
                    detail: "Unlock this Space before viewing or changing its installed extensions.")
            }
        }
        .onAppear { if selectedSpaceID == nil { selectedSpaceID = requestedSpaceID ?? browser.selectedSpaceID } }
        .onChange(of: requestRevision) { selectedSpaceID = requestedSpaceID ?? browser.selectedSpaceID }
        .onChange(of: browser.session.spaces.map(\.id)) {
            if !browser.session.spaces.contains(where: { $0.id == selectedSpaceID }) { selectedSpaceID = browser.selectedSpaceID }
        }
    }
}

struct BrowserExtensionsView: View {
    let space: BrowserSpace
    let store: ChromiumExtensionStore
    @State private var failure: String?
    @State private var pendingRemoval: ChromiumExtensionStore.Installed?
    @State private var pendingCopy: ChromiumExtensionStore.Installed?
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    private var extensions: [ChromiumExtensionStore.Installed] {
        (store.installed[space.profile.id] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        Group {
            if !usesLiveSidebar { installedExtensions }
            Section("Add Extensions", systemImage: "plus.app") {
                Button("Open Chrome Web Store", systemImage: "arrow.up.right.square") { run("store") }
                Text("Choose an extension, then use Install Extension in Site Controls to review its permissions and select Spaces.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Chromium Extension Manager", systemImage: "arrow.up.right.square") { run("manage") }
                // Extension shortcuts are the engine's own bindings: Crest routes an
                // unclaimed key equivalent to them but does not own their list.
                Button("Keyboard Shortcuts…", systemImage: "keyboard") { run("shortcuts") }
            }
            if usesLiveSidebar { installedExtensions }
        }
        .task(id: space.profile.id) { await store.load(space) }
        .alert("Couldn’t Complete Extension Action", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
        .confirmationDialog("Remove Extension?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), presenting: pendingRemoval) { item in
            Button("Remove from \(space.name)", role: .destructive) { run("remove", item.id); pendingRemoval = nil }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { item in Text("\(item.name) and its Space-local data will be removed. Other Spaces are unchanged.") }
        .sheet(item: $pendingCopy) { item in BrowserExtensionCopySheet(item: item, space: space, store: store) }
    }
    private var installedExtensions: some View {
        Section("Installed in this Space", systemImage: "puzzlepiece.extension") {
            Label("Extensions and their data belong to \(space.name).", systemImage: "square.grid.2x2")
                .font(.callout).foregroundStyle(.secondary)
            if store.installed[space.profile.id] == nil { ProgressView() }
            else if extensions.isEmpty { ContentUnavailableView("No Extensions", systemImage: "puzzlepiece.extension", description: Text("Install an extension for this Space to get started.")) }
            else {
                ForEach(extensions) { item in
                    BrowserExtensionRow(item: item, setEnabled: { run($0 ? "enable" : "disable", item.id) },
                        options: { run("options", item.id) }, manage: { run("details", item.id) },
                        remove: { pendingRemoval = item }, copy: { pendingCopy = item })
                }
            }
        }.containerValue(\.settingsFullWidth, true)
    }
    private func run(_ command: String, _ id: String = "") {
        if !store.command(command, extensionID: id, space: space) {
            failure = "Chromium could not complete this action. Check the extension’s details for policy or permission requirements."
        }
    }
}

/// Preserves Crest's disclosure row, artwork, version, description, and toggle.
struct BrowserExtensionRow: View {
    let item: ChromiumExtensionStore.Installed
    let setEnabled: (Bool) -> Void
    let options: () -> Void
    let manage: () -> Void
    let remove: () -> Void
    let copy: () -> Void
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                if item.webStore { Button("Install a copy in other spaces", action: copy) }
                if !item.permissions.isEmpty {
                    VStack(alignment: .leading, spacing: CrestSpacing.small) {
                        Text("Permissions and Website Access").font(.headline)
                        ForEach(item.permissions, id: \.self) { Text($0).font(.callout).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                Button("Manage Permissions in Chromium", systemImage: "hand.raised", action: manage)
                if !item.options.isEmpty && item.enabled { Button("Extension Settings", systemImage: "gearshape", action: options) }
                Button("Remove Extension", systemImage: "trash", role: .destructive, action: remove)
            }
            .padding(.top, CrestSpacing.medium)
            .padding(.leading, BrowserExtensionsMetrics.expandedContentIndent)
        } label: {
            HStack(alignment: .center, spacing: CrestSpacing.medium) {
                BrowserExtensionIconView(image: item.icon)
                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    HStack(spacing: CrestSpacing.small) {
                        Text(item.name).font(.body.weight(.medium))
                        Text(item.version).font(.caption).foregroundStyle(.tertiary)
                    }
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if item.webStore { Text("From Chrome Web Store").font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Toggle("Enabled", isOn: Binding(get: { item.enabled }, set: setEnabled))
                    .labelsHidden().accessibilityLabel("\(item.name) Enabled")
            }
        }.padding(.vertical, CrestSpacing.extraSmall)
    }
}

struct BrowserExtensionCopySheet: View {
    let item: ChromiumExtensionStore.Installed
    let space: BrowserSpace
    let store: ChromiumExtensionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSpaces: Set<SpaceID> = []
    @State private var loading = true
    private var destinations: [BrowserSpace] {
        store.spaces.filter { $0.id != space.id && !(store.installed[$0.profile.id] ?? []).contains { $0.id == item.id } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            Text("Install a Copy in Other Spaces").font(.title2.bold())
            Text(item.name).font(.headline)
            Text("Each Space keeps its own extension data; existing data is not copied. Review the verified package and permissions before installing.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            BrowserExtensionSpaceSelectionList(spaces: destinations, selection: $selectedSpaces).disabled(loading)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button("Review Installation") {
                    let targets = destinations.filter { selectedSpaces.contains($0.id) }
                    guard let first = targets.first else { return }
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        store.install(item.id, in: first, anchor: nil, copies: Set(targets.dropFirst().map(\.id)))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading || selectedSpaces.intersection(Set(destinations.map(\.id))).isEmpty)
            }
        }
        .padding(CrestSpacing.extraLarge)
        .frame(idealWidth: 480)
        .task { for target in store.spaces { await store.load(target) }; loading = false }
    }
}
