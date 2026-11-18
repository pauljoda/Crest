import Foundation
import Observation
import SwiftUI

/// The platform's side of the manual setup the core holds for this device:
/// the setup as the core last published it, and the intents the person's
/// edits send. The core keeps the setup, its rules and, on a platform that
/// keeps one, the unfinished setup for the next launch; a refused edit shows
/// the core's own words.
@MainActor
@Observable
final class BrowserManualSetupModel {
    // MARK: - Variables

    let core: CrestCore
    /// Why the last edit was refused, until the next one succeeds.
    var errorMessage: String?

    /// The setup in progress, or nil before it starts and once it ends.
    var draft: SetupDraft? { core.state.setupDraft }

    /// The setup's Spaces in its order.
    var spaces: [SetupDraftSpace] { draft?.spaces ?? [] }

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
    }

    // MARK: - Actions - Setup

    /// Adds a new Space and answers it, or nil when the core refused it.
    @discardableResult
    func addSpace() -> UUID? {
        guard send(AddSetupSpace(fromSpaceID: nil)) else { return nil }
        return spaces.last?.spaceID
    }

    /// Adds a Sub-Space of `spaceID`, sharing its group's session, and
    /// answers it, or nil when the core refused it.
    @discardableResult
    func addSubSpace(to spaceID: UUID) -> UUID? {
        let before = Set(spaces.map(\.spaceID))
        guard send(AddSetupSpace(fromSpaceID: spaceID)) else { return nil }
        return spaces.first { !before.contains($0.spaceID) }?.spaceID
    }

    /// Takes the new Space `spaceID` out of the setup.
    func removeSpace(_ spaceID: UUID) {
        send(RemoveSetupSpace(spaceID: spaceID))
    }

    /// Moves `spaceID` to where `targetID` is in the setup's order.
    func moveSpace(_ spaceID: UUID, to targetID: UUID) {
        send(MoveSetupSpace(spaceID: spaceID, targetSpaceID: targetID))
    }

    /// The setup's Space `spaceID`, or nil when the setup no longer holds it.
    func space(_ spaceID: UUID?) -> SetupDraftSpace? {
        spaces.first { $0.spaceID == spaceID }
    }

    // MARK: - Actions - Bindings

    func nameBinding(for spaceID: UUID) -> Binding<String> {
        Binding(
            get: { self.space(spaceID)?.customization.name ?? "" },
            set: { name in
                self.customize(spaceID) {
                    SpaceCustomization(name: name, symbol: $0.symbol, accent: $0.accent, branding: $0.branding)
                }
            }
        )
    }

    func symbolBinding(for spaceID: UUID) -> Binding<String> {
        Binding(
            get: { self.space(spaceID)?.customization.symbol ?? "" },
            set: { symbol in
                self.customize(spaceID) {
                    SpaceCustomization(name: $0.name, symbol: symbol, accent: $0.accent, branding: $0.branding)
                }
            }
        )
    }

    func brandingBinding(for spaceID: UUID) -> Binding<SpaceBranding> {
        Binding(
            get: {
                self.space(spaceID).map(\.customization.branding)
                    ?? SpaceAccent.indigo.house
            },
            set: { branding in
                self.customize(spaceID) {
                    SpaceCustomization(name: $0.name, symbol: $0.symbol, accent: $0.accent, branding: branding)
                }
            }
        )
    }

    private func customize(_ spaceID: UUID, _ edit: (SpaceCustomization) -> SpaceCustomization) {
        guard let space = space(spaceID) else { return }
        send(CustomizeSetupSpace(spaceID: spaceID, customization: edit(space.customization)))
    }

    // MARK: - Actions - Sending

    /// Sends `intent`, keeping the core's words when it refuses it.
    @discardableResult
    private func send(_ intent: some Intent) -> Bool {
        do {
            _ = try core.send(intent)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.explanation
            return false
        }
    }
}
