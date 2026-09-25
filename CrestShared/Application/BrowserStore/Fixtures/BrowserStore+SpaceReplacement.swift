#if DEBUG
    import Foundation

    extension BrowserStore {
        /// Deletes the Space `spaceID` whole, as the app does once the platform
        /// has erased its profile's data, for tests of what an assignment
        /// captured before it may still do.
        func removeSpaceForTesting(_ spaceID: SpaceID) {
            let operation = UUID()
            let window = windowID.rawValue
            do {
                try family.commit(
                    BeginDeletingSpace(
                        workspaceID: family.workspaceID, windowID: window, spaceID: spaceID.rawValue,
                        operationID: operation), from: self)
                try family.commit(
                    FinishDeletingSpace(
                        workspaceID: family.workspaceID, windowID: window, spaceID: spaceID.rawValue,
                        operationID: operation), from: self)
            } catch {
                preconditionFailure("The core refused to remove a Space for a test: \(error)")
            }
        }

        /// Gives the Space `spaceID` the profile `profileID`, as only a cloud
        /// replacement can: the Space goes, then comes back whole under the new
        /// profile, in its place in the order, and this window shows what it
        /// showed. For tests of what an assignment captured before the
        /// replacement may still do. The workspace takes imports, so it is a
        /// persistent one.
        func replaceProfileForTesting(of spaceID: SpaceID, with profileID: UUID = UUID()) {
            guard let space = session.space(id: spaceID) else {
                preconditionFailure("A test replaced the profile of a Space the session does not hold.")
            }
            let order = session.spaces.map(\.id.rawValue)
            let shownSpace = selectedSpaceID
            let shownTab = selectedTabID(in: spaceID)
            let replacement = BrowserSpace(
                id: space.id, profile: BrowsingProfile(id: profileID), name: space.name, symbol: space.symbol,
                accent: space.accent, branding: space.branding, folders: space.folders, tabs: space.tabs,
                splitGroups: space.splitGroups, archivedTabs: space.archivedTabs, history: space.history,
                browsingPreferences: space.browsingPreferences, credentialPreferences: space.credentialPreferences,
                accessPolicy: space.accessPolicy, isSavedTabsExpanded: space.isSavedTabsExpanded,
                savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt)
            // A Space is never the last one while it goes.
            let placeholder = SpaceID()
            if session.spaces.count == 1 {
                _ = family.send(
                    CreateSpace(
                        workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: placeholder.rawValue),
                    from: self)
            }
            removeSpaceForTesting(spaceID)
            do {
                try family.importSpaces(
                    ImportSpaces(
                        workspaceID: family.workspaceID, windowID: windowID.rawValue,
                        spaces: try BrowserSpace.storedFormat([replacement])),
                    from: [replacement], issuedBy: self)
            } catch {
                preconditionFailure("The core refused to bring a Space back for a test: \(error)")
            }
            if session.space(id: placeholder) != nil { removeSpaceForTesting(placeholder) }
            family.send(ReorderSpaces(workspaceID: family.workspaceID, spaceIDs: order), from: self)
            selectPresentedSpace(shownSpace)
            if let shownTab { activateSessionTab(shownTab, in: spaceID) }
        }
    }
#endif
