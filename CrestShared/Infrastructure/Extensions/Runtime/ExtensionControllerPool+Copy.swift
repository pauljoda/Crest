import Foundation

extension BrowserExtensionControllerPool {
    func copyDestinations(extensionID: String, excluding sourceSpace: SpaceID) -> [BrowserSpace] {
        installationSpaces().filter {
            $0.id != sourceSpace && persistenceController.installation(extensionID: extensionID, in: $0.id) == nil
        }
    }

    func copyExtension(extensionID: String, from sourceSpace: SpaceID, to spaceIDs: Set<SpaceID>) async throws {
        guard !spaceIDs.isEmpty else { return }
        guard installationSpaces().contains(where: { $0.id == sourceSpace }) else {
            throw CopyFailure(details: String(localized: "Unlock the source Space before copying its extensions."))
        }
        var failures: [String] = []
        // Resolve again at execution time so a locked or deleted Space cannot
        // be accessed using a selection made while it was available.
        for id in spaceIDs {
            let availableSpaces = installationSpaces()
            guard availableSpaces.contains(where: { $0.id == sourceSpace }) else {
                failures.append(String(localized: "Unlock the source Space before copying its extensions."))
                break
            }
            guard let space = availableSpaces.first(where: { $0.id == id }), id != sourceSpace else {
                failures.append(String(localized: "A selected Space is no longer available."))
                continue
            }
            // A completed copy is retained and skipped on retry.
            if persistenceController.installation(extensionID: extensionID, in: id) != nil { continue }
            do {
                _ = try await installationController.copyExtension(
                    extensionID: extensionID, from: sourceSpace, to: space,
                    validateAccess: { [self] in
                        try Task.checkCancellation()
                        let available = installationSpaces()
                        guard available.contains(where: { $0.id == sourceSpace }),
                            available.contains(where: { $0.id == id })
                        else {
                            throw CopyFailure(details: String(localized: "A selected Space is no longer available."))
                        }
                    })
            } catch {
                failures.append("\(space.name): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { throw CopyFailure(details: failures.joined(separator: "\n")) }
    }

    private struct CopyFailure: LocalizedError {
        let details: String
        var errorDescription: String? {
            String(localized: "Some copies could not be installed. Completed installations were kept.") + "\n" + details
        }
    }
}
