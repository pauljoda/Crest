#if CREST_CHROMIUM_HOST
    import Foundation

    @MainActor
    final class ChromiumDownloadAdapter: BrowserEngineDownloadControlling {
        struct Destination {
            let center: BrowserDownloadCenter
            let assignment: BrowserSpaceRuntimeAssignment
        }
        private let host: any CrestChromiumEngineHost
        private let resolve: ([String: Any], UUID) -> Destination?
        private struct CachedDestination {
            weak var center: BrowserDownloadCenter?
            let assignment: BrowserSpaceRuntimeAssignment
        }
        private var destinations: [BrowserEngineDownloadID: CachedDestination] = [:]

        init(
            host: any CrestChromiumEngineHost,
            resolve: @escaping ([String: Any], UUID) -> Destination?
        ) {
            self.host = host
            self.resolve = resolve
            host.setDownloadObserver { [weak self] values in
                MainActor.assumeIsolated { _ = self?.receive(values) }
            }
            host.setDownloadDestinationResolver { [weak self] values, reply in
                MainActor.assumeIsolated {
                    guard let self, let (id, destination) = self.receive(values) else {
                        reply(nil)
                        return
                    }
                    Task { @MainActor in
                        let url = await destination.center.resolveEngineDownloadDestination(
                            id,
                            suggestedFilename: values["filename"] as? String ?? "download",
                            forcesPrompt: values["forcePrompt"] as? Bool == true)
                        reply(url?.path)
                    }
                }
            }
        }

        @discardableResult
        private func receive(_ values: [String: Any]) -> (BrowserEngineDownloadID, Destination)? {
            guard let profileID = (values["profileId"] as? String).flatMap(UUID.init(uuidString:)),
                let value = values["downloadId"] as? String
            else { return nil }
            let id = BrowserEngineDownloadID(engine: .chromium, profileID: profileID, value: value)
            let target: Destination?
            if let cached = destinations[id] {
                target = cached.center.map { Destination(center: $0, assignment: cached.assignment) }
            } else {
                target = resolve(values, profileID)
            }
            guard let destination = target else {
                cancelDownload(id)
                return nil
            }
            destinations[id] = CachedDestination(center: destination.center, assignment: destination.assignment)
            let state: BrowserEngineDownloadUpdate.State
            // A state this build does not know is still being prepared.
            switch (values["state"] as? String).flatMap(ChromiumDownloadState.init(rawValue:)) {
            case .finished: state = .finished
            case .canceled: state = .canceled
            case .failed: state = .failed(values["message"] as? String ?? "The download failed.")
            case .warning:
                guard let token = values["warningToken"] as? String,
                    let message = values["message"] as? String
                else {
                    cancelDownload(id)
                    return nil
                }
                state = .awaitingApproval(token: token, message: message)
            case .downloading: state = .downloading
            case .preparing, nil: state = .preparing
            }
            let path = values["path"] as? String ?? ""
            destination.center.receiveEngineDownload(
                BrowserEngineDownloadUpdate(
                    id: id,
                    filename: values["filename"] as? String ?? "download",
                    destination: path.isEmpty ? nil : URL(fileURLWithPath: path),
                    bytesReceived: (values["received"] as? NSNumber)?.int64Value ?? 0,
                    totalBytes: (values["total"] as? NSNumber)?.int64Value ?? 0,
                    isPaused: values["paused"] as? Bool == true, state: state,
                    // The core only records finite dates.
                    createdAt: (values["startedAt"] as? NSNumber).map(\.doubleValue).flatMap {
                        $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
                    } ?? .now,
                    isRestored: values["restored"] as? Bool == true),
                assignment: destination.assignment, controller: self)
            return (id, destination)
        }

        func cancelDownload(_ id: BrowserEngineDownloadID) {
            guard id.engine == .chromium else { return }
            host.cancelDownload(id.value, profile: id.profileID.uuidString)
        }
        func removeDownload(_ id: BrowserEngineDownloadID) {
            guard id.engine == .chromium else { return }
            host.removeDownload(id.value, profile: id.profileID.uuidString)
        }
        func approveDownload(_ id: BrowserEngineDownloadID, warningToken: String) {
            guard id.engine == .chromium else { return }
            host.approveDownload(id.value, profile: id.profileID.uuidString, warning: warningToken)
        }
    }

    /// A download's state in the host's download observations.
    private enum ChromiumDownloadState: String {
        case preparing
        case downloading
        case warning
        case finished
        case canceled
        case failed
    }
#endif
