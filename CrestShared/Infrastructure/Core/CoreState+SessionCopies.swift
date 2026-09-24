#if DEBUG
    import Foundation

    /// TRANSITIONAL until S6.7 deletes the Swift session copy. After each
    /// batch, every part of a workspace a change in it touched must read in
    /// the read model as it reads in that workspace's copy, through the copy's
    /// own readers of the core's records. A part a change touches is compared
    /// whole. A mismatch stops a debug build, naming the workspace, the Space,
    /// the part and the first record that differs.
    extension CoreState {
        // MARK: - Types

        /// The parts of one workspace a batch touched.
        private struct TouchedWorkspace {
            var isWhole = false
            var hasMembers = false
            /// A change named a tab but not its Space.
            var hasTabsEverywhere = false
            var spaces: [UUID: SpaceParts] = [:]
        }

        private struct SpaceParts: OptionSet {
            let rawValue: Int

            static let settings = SpaceParts(rawValue: 1 << 0)
            static let tabs = SpaceParts(rawValue: 1 << 1)
            static let folders = SpaceParts(rawValue: 1 << 2)
            static let splits = SpaceParts(rawValue: 1 << 3)
            static let history = SpaceParts(rawValue: 1 << 4)
            static let archive = SpaceParts(rawValue: 1 << 5)
            static let all: SpaceParts = [.settings, .tabs, .folders, .splits, .history, .archive]
        }

        // MARK: - Actions - Checking

        /// Checks every registered copy against the read model where `changes`
        /// touched it.
        func checkSessionCopies(after changes: [Change]) {
            for (workspaceID, touched) in Self.touched(by: changes) {
                guard let copy = sessionCopies[workspaceID]?.authority?.projection else { continue }
                guard let workspace = workspaces[workspaceID] else {
                    assertionFailure(
                        "Read model parity, workspace \(workspaceID): the copy holds a session the read model lacks.")
                    continue
                }
                var problems = touched.isWhole || touched.hasMembers ? memberProblems(workspace, copy) : []
                var parts = touched.spaces
                if touched.isWhole || touched.hasTabsEverywhere {
                    let every = Set(workspace.spaces.models.map(\.id)).union(copy.spaces.map(\.id.rawValue))
                    for spaceID in every { parts[spaceID, default: []].formUnion(touched.isWhole ? .all : .tabs) }
                }
                for (spaceID, touchedParts) in parts {
                    problems += spaceProblems(spaceID, parts: touchedParts, in: workspace, copy: copy)
                }
                if !problems.isEmpty {
                    assertionFailure("Read model parity, workspace \(workspaceID): \(problems.joined(separator: "; "))")
                }
            }
        }

        private static func touched(by changes: [Change]) -> [UUID: TouchedWorkspace] {
            var touched: [UUID: TouchedWorkspace] = [:]
            for change in changes {
                switch change {
                case .workspaceOpened(let opened):
                    touched[opened.workspaceID, default: TouchedWorkspace()].isWhole = true
                case .workspaceChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].hasMembers = true
                case .appPreferencesChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].hasMembers = true
                case .spacesChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].hasMembers = true
                    for space in changed.added {
                        touched[changed.workspaceID, default: TouchedWorkspace()].spaces[space.id] = .all
                    }
                case .spaceSettingsChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].spaces[changed.spaceID, default: []]
                        .insert(.settings)
                case .tabsChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].spaces[changed.spaceID, default: []]
                        .insert(.tabs)
                case .foldersChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].spaces[changed.spaceID, default: []]
                        .insert(.folders)
                case .splitGroupsChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].spaces[changed.spaceID, default: []]
                        .insert(.splits)
                case .historyChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].spaces[changed.spaceID, default: []]
                        .insert(.history)
                case .archiveChanged(let changed):
                    touched[changed.workspaceID, default: TouchedWorkspace()].spaces[changed.spaceID, default: []]
                        .insert(.archive)
                case .tabCopied(let copied):
                    touched[copied.workspaceID, default: TouchedWorkspace()].hasTabsEverywhere = true
                case .tabsImported(let imported):
                    touched[imported.workspaceID, default: TouchedWorkspace()].isWhole = true
                case .tabFaviconAssigned(let assigned):
                    touched[assigned.workspaceID, default: TouchedWorkspace()].hasTabsEverywhere = true
                default:
                    break
                }
            }
            return touched
        }

        private func memberProblems(_ workspace: WorkspaceModel, _ copy: BrowserSession) -> [String] {
            var problems: [String] = []
            let order = workspace.spaces.models.map(\.id)
            let copyOrder = copy.spaces.map(\.id.rawValue)
            if order != copyOrder { problems.append("Spaces: read model \(order), copy \(copyOrder)") }
            if workspace.defaultSpaceID != copy.defaultSpaceID?.rawValue {
                problems.append(
                    "default Space: read model \(String(describing: workspace.defaultSpaceID)), "
                        + "copy \(String(describing: copy.defaultSpaceID))")
            }
            if workspace.isDisposableSeed != (copy.disposableSeedMarker != nil) {
                problems.append(
                    "disposable seed: read model \(workspace.isDisposableSeed), copy \(copy.disposableSeedMarker != nil)"
                )
            }
            let deletions =
                workspace.spaceDeletions.isEmpty
                ? nil : workspace.spaceDeletions.map(BrowserSpaceDeletionIntent.init(core:))
            if deletions != copy.spaceDeletions {
                problems.append(
                    "Space deletions: read model \(String(describing: deletions)), "
                        + "copy \(String(describing: copy.spaceDeletions))")
            }
            let preferences = workspace.appPreferences.map(BrowserAppPreferences.init(core:))
            if preferences != copy.appPreferences {
                problems.append(
                    "app preferences differ in \(Self.differences(preferences as Any, copy.appPreferences as Any))")
            }
            return problems
        }

        private func spaceProblems(
            _ spaceID: UUID, parts: SpaceParts, in workspace: WorkspaceModel, copy: BrowserSession
        ) -> [String] {
            let space = workspace.spaces.model(spaceID)
            let copySpace = copy.space(id: SpaceID(rawValue: spaceID))
            guard let space, let copySpace else {
                if space == nil && copySpace == nil { return [] }
                return ["Space \(spaceID): only the \(space == nil ? "copy" : "read model") holds it"]
            }
            var problems: [String] = []
            if parts.contains(.settings) {
                var configured = copySpace
                configured.configure(core: space.settings.value)
                if space.profileID != copySpace.profile.id {
                    problems.append(
                        "Space \(spaceID) profile: read model \(space.profileID), copy \(copySpace.profile.id)")
                }
                if configured != copySpace {
                    problems.append("Space \(spaceID) settings differ in \(Self.differences(configured, copySpace))")
                }
            }
            if parts.contains(.tabs) {
                let tabs = space.tabs.models.map { BrowserTab(core: $0.value, faviconData: favicons.image(of: $0.id)) }
                problems += Self.rowProblems("Space \(spaceID) tabs", tabs, copySpace.tabs) { $0.id.rawValue }
            }
            if parts.contains(.folders) {
                let folders = space.folders.models.map { BrowserFolder(core: $0.value) }
                problems += Self.rowProblems("Space \(spaceID) folders", folders, copySpace.folders) { $0.id.rawValue }
            }
            if parts.contains(.splits) {
                let splits = BrowserSplitGroupMetadata.normalized(
                    space.splitGroups.map(BrowserSplitGroupMetadata.init(core:)))
                problems += Self.rowProblems(
                    "Space \(spaceID) splits", splits, BrowserSplitGroupMetadata.normalized(copySpace.splitGroups)
                ) { $0.id.rawValue }
            }
            if parts.contains(.history) {
                let history = space.history.entries.compactMap(BrowserHistoryEntry.init(core:))
                problems += Self.rowProblems("Space \(spaceID) history", history, copySpace.history) { $0.id }
            }
            if parts.contains(.archive) {
                let archive = space.archive.entries.map {
                    ArchivedTab(
                        tab: BrowserTab(core: $0.tab, faviconData: favicons.image(of: $0.tab.id)),
                        archivedAt: $0.archivedAt, reason: $0.reason)
                }
                problems += Self.rowProblems("Space \(spaceID) archive", archive, copySpace.archivedTabs) {
                    $0.id.rawValue
                }
            }
            return problems
        }

        /// The first difference between two lists of rows: their identities,
        /// or else the first row that differs and in which fields.
        private static func rowProblems<Row: Equatable>(
            _ part: String, _ rows: [Row], _ copyRows: [Row], id: (Row) -> UUID
        ) -> [String] {
            guard rows != copyRows else { return [] }
            let ids = rows.map(id)
            let copyIDs = copyRows.map(id)
            guard ids == copyIDs else { return ["\(part): read model holds \(ids), copy holds \(copyIDs)"] }
            guard let pair = zip(rows, copyRows).first(where: { $0.0 != $0.1 }) else { return [] }
            return ["\(part): \(id(pair.0)) differs in \(differences(pair.0, pair.1))"]
        }

        /// The fields in which two values of one type differ, with each side's value.
        private static func differences(_ value: Any, _ copyValue: Any) -> String {
            let fields = zip(Mirror(reflecting: value).children, Mirror(reflecting: copyValue).children)
                .filter { String(describing: $0.value) != String(describing: $1.value) }
                .map { "\($0.label ?? "value"): read model \($0.value), copy \($1.value)" }
            return fields.isEmpty ? "a value its description hides" : fields.joined(separator: ", ")
        }
    }
#endif
