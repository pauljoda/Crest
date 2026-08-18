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
    private(set) var isScanningInstalled = false
    private(set) var didScanInstalled = false
    private(set) var needsSafariCustomExtensionAccess = false
    private(set) var statusMessage: String?
    private(set) var operationFailure: BrowserExtensionOperationFailure?

    var installableItems: [BrowserExtensionDiscoveryItem] {
        let installedIDs = Set(extensionsModel.extensions.map(\.id))
        return discoveryItems.filter { !installedIDs.contains($0.id) }
    }

    var isBusy: Bool {
        isScanningInstalled
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

    func chooseSafariCustomExtensionFolder() {
        BrowserSafariCustomExtensionFilePicker.chooseFolder {
            [weak self] directoryURL in
            guard let self, let directoryURL else { return }
            Task {
                await self.inspectSafariCustomExtensionFolder(
                    from: .success([directoryURL])
                )
            }
        }
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

    func inspectSafariCustomExtensionFolder(
        from result: Result<[URL], any Error>
    ) async {
        do {
            guard let directoryURL = try result.get().first else { return }
            isScanningInstalled = true
            defer { isScanningInstalled = false }
            let hasSecurityScope =
                directoryURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }
            let result = try await scanSafariCustomExtensions(
                at: directoryURL
            )
            try BrowserSafariCustomExtensionAccessStore.remember(
                directoryURL
            )
            merge(result.candidates)
            needsSafariCustomExtensionAccess = false
            statusMessage = rejectionMessage(
                customExtensionCount: result.rejectedCount
            )
        } catch {
            publishFailure(error)
        }
    }

    func scanInstalled() async {
        guard !isScanningInstalled else { return }
        isScanningInstalled = true
        didScanInstalled = false
        statusMessage = nil
        defer {
            isScanningInstalled = false
            didScanInstalled = true
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

        let customRoot =
            BrowserSafariCustomExtensionAccessStore.resolve()
            ?? BrowserSafariCustomExtensionScanner.defaultSearchRoot
        let hasSecurityScope =
            customRoot.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                customRoot.stopAccessingSecurityScopedResource()
            }
        }
        var customCandidates: [BrowserLocalExtensionCandidate] = []
        var rejectedCustomExtensionCount = 0
        do {
            let result = try await scanSafariCustomExtensions(at: customRoot)
            customCandidates = result.candidates
            rejectedCustomExtensionCount = result.rejectedCount
            needsSafariCustomExtensionAccess = false
        } catch {
            needsSafariCustomExtensionAccess = true
            BrowserSafariCustomExtensionAccessStore.clear()
        }
        replace(
            safariApplications: candidates,
            safariCustomExtensions: customCandidates
        )
        statusMessage = rejectionMessage(
            applicationCount: rejectedApplicationCount,
            customExtensionCount: rejectedCustomExtensionCount
        )
    }

    func install(
        _ item: BrowserExtensionDiscoveryItem
    ) async {
        guard installingExtensionID == nil else { return }
        installingExtensionID = item.id
        defer { installingExtensionID = nil }
        do {
            switch item.candidate {
            case .safariApplication(let candidate):
                try await extensionsModel.extensionControllerPool
                    .installSafariWebExtension(
                        candidate,
                        in: extensionsModel.space
                    )
            case .safariCustom(let candidate):
                try await extensionsModel.extensionControllerPool
                    .installLocalExtension(
                        candidate,
                        in: extensionsModel.space
                    )
            }
            discoveryItems.removeAll { $0.id == item.id }
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

    private func merge(
        _ candidates: [BrowserLocalExtensionCandidate]
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
        safariApplications: [BrowserSafariWebExtensionCandidate],
        safariCustomExtensions: [BrowserLocalExtensionCandidate]
    ) {
        discoveryItems = sorted(
            safariApplications.map(
                BrowserExtensionDiscoveryItem.init(candidate:)
            )
                + safariCustomExtensions.map(
                    BrowserExtensionDiscoveryItem.init(candidate:)
                )
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

    private func scanSafariCustomExtensions(
        at searchRoot: URL
    ) async throws -> (
        candidates: [BrowserLocalExtensionCandidate],
        rejectedCount: Int
    ) {
        let scanResult = try await Task.detached(
            priority: .userInitiated
        ) {
            try BrowserSafariCustomExtensionScanner()
                .scan(searchRoot: searchRoot)
        }.value
        let provider = BrowserSafariCustomExtensionProvider()
        var candidates: [BrowserLocalExtensionCandidate] = []
        var rejectedCount = scanResult.rejectedExtensionCount
        for package in scanResult.packages {
            do {
                candidates.append(
                    try await provider.candidate(for: package)
                )
            } catch {
                rejectedCount += 1
            }
        }
        return (candidates, rejectedCount)
    }

    private func rejectionMessage(
        applicationCount: Int = 0,
        customExtensionCount: Int = 0
    ) -> String? {
        var messages: [String] = []
        if applicationCount > 0 {
            let noun = applicationCount == 1 ? "app" : "apps"
            messages.append(
                "\(applicationCount) additional \(noun) couldn’t pass signature or WebKit verification"
            )
        }
        if customExtensionCount > 0 {
            let noun =
                customExtensionCount == 1
                ? "Safari custom extension"
                : "Safari custom extensions"
            messages.append(
                "\(customExtensionCount) \(noun) couldn’t pass safe file or WebKit inspection"
            )
        }
        guard !messages.isEmpty else { return nil }
        return "Crest skipped " + messages.joined(separator: " and ") + "."
    }
}
