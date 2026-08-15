import Foundation
import Observation

@Observable
@MainActor
final class BrowserExtensionDiscoveryModel {
    let extensionsModel: BrowserExtensionsModel

    var isChoosingSafariApplication = false
    private(set) var discoveryItems: [BrowserExtensionDiscoveryItem] = []
    private(set) var installingExtensionID: String?
    private(set) var isInspectingApplication = false
    private(set) var isScanningApplications = false
    private(set) var didScanApplications = false
    private(set) var statusMessage: String?
    private(set) var operationFailure: BrowserExtensionOperationFailure?

    var installableItems: [BrowserExtensionDiscoveryItem] {
        let installedIDs = Set(extensionsModel.extensions.map(\.id))
        return discoveryItems.filter { !installedIDs.contains($0.id) }
    }

    var isBusy: Bool {
        isScanningApplications
            || isInspectingApplication
            || extensionsModel.isLoadingExtension
            || installingExtensionID != nil
    }

    init(extensionsModel: BrowserExtensionsModel) {
        self.extensionsModel = extensionsModel
    }

    func chooseUnpackedExtension() {
        extensionsModel.isChoosingExtension = true
    }

    func inspectSafariApplication(
        from result: Result<[URL], any Error>
    ) async {
        do {
            guard let applicationURL = try result.get().first else { return }
            isInspectingApplication = true
            defer { isInspectingApplication = false }

            let hasSecurityScope =
                applicationURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    applicationURL.stopAccessingSecurityScopedResource()
                }
            }
            let candidates = try await BrowserSafariWebExtensionInspector()
                .inspect(applicationURL: applicationURL)
            merge(candidates)
            statusMessage = nil
        } catch {
            publishFailure(error)
        }
    }

    func scanApplications() async {
        guard !isScanningApplications else { return }
        isScanningApplications = true
        didScanApplications = false
        statusMessage = nil
        defer {
            isScanningApplications = false
            didScanApplications = true
        }

        let roots = BrowserSafariWebExtensionApplicationScanner
            .defaultSearchRoots
        let matches = await Task.detached(priority: .userInitiated) {
            BrowserSafariWebExtensionApplicationScanner()
                .scan(searchRoots: roots)
        }.value

        var candidates: [BrowserSafariWebExtensionCandidate] = []
        var rejectedApplicationCount = 0
        for match in matches {
            do {
                candidates += try await BrowserSafariWebExtensionInspector()
                    .inspect(applicationURL: match.applicationURL)
            } catch {
                rejectedApplicationCount += 1
            }
        }
        replace(with: candidates)
        if rejectedApplicationCount > 0 {
            let noun = rejectedApplicationCount == 1 ? "app" : "apps"
            statusMessage =
                "Crest found \(rejectedApplicationCount) additional \(noun) that couldn’t pass signature or WebKit verification."
        }
    }

    func install(
        _ candidate: BrowserSafariWebExtensionCandidate
    ) async {
        guard installingExtensionID == nil else { return }
        installingExtensionID = candidate.id
        defer { installingExtensionID = nil }
        do {
            try await extensionsModel.extensionControllerPool
                .installSafariWebExtension(
                    candidate,
                    in: extensionsModel.space
                )
            discoveryItems.removeAll { $0.id == candidate.id }
        } catch {
            publishFailure(error)
        }
    }

    func clearOperationFailure() {
        operationFailure = nil
    }

    private func merge(
        _ candidates: [BrowserSafariWebExtensionCandidate]
    ) {
        var itemsByID = Dictionary(
            uniqueKeysWithValues: discoveryItems.map { ($0.id, $0) }
        )
        for candidate in candidates {
            itemsByID[candidate.id] = BrowserExtensionDiscoveryItem(
                candidate: candidate
            )
        }
        discoveryItems = sorted(Array(itemsByID.values))
    }

    private func replace(
        with candidates: [BrowserSafariWebExtensionCandidate]
    ) {
        discoveryItems = sorted(
            candidates.map(BrowserExtensionDiscoveryItem.init(candidate:))
        )
    }

    private func sorted(
        _ items: [BrowserExtensionDiscoveryItem]
    ) -> [BrowserExtensionDiscoveryItem] {
        items.sorted {
            $0.candidate.displayName.localizedStandardCompare(
                $1.candidate.displayName
            ) == .orderedAscending
        }
    }

    private func publishFailure(_ error: any Error) {
        operationFailure = BrowserExtensionOperationFailure(
            message: error.localizedDescription
        )
    }
}
