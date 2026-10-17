import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

/// What the share sheet's Crest entry is doing with the link another app
/// shared: reading it, asking for a Space, or telling the person it waits in
/// Crest.
@Observable
@MainActor
final class CrestShareModel {
    // MARK: - Types

    enum Stage: Equatable {
        /// Reading the shared items, or handing the link to Crest.
        case working
        /// Asking which Space the link opens in.
        case choosingSpace(BrowserSharedLink, BrowserSharedSpaceDirectory)
        /// Crest could not be opened, so the link waits for it.
        case saved
        /// The shared items hold no web link.
        case noLink
        /// Crest could not be opened and this build has nowhere to keep the link.
        case couldNotOpen
    }

    // MARK: - Variables

    private(set) var stage = Stage.working
    var selectedSpaceID: UUID?
    /// The icons Crest rendered for the Spaces it offers.
    private(set) var spaceIcons: [UUID: UIImage] = [:]

    private let container: BrowserLinkSharingContainer?
    private let openInCrest: @MainActor (URL) async -> Bool
    private let finish: @MainActor () -> Void

    // MARK: - Initializers

    init(
        container: BrowserLinkSharingContainer?,
        openInCrest: @escaping @MainActor (URL) async -> Bool,
        finish: @escaping @MainActor () -> Void
    ) {
        self.container = container
        self.openInCrest = openInCrest
        self.finish = finish
    }

    // MARK: - Actions - Sharing

    /// Reads the link from what another app shared, then opens it or asks
    /// for a Space, as the person chose in Crest's settings.
    func receive(_ providers: [NSItemProvider]) async {
        guard let link = await Self.sharedLink(in: providers) else {
            stage = .noLink
            return
        }
        guard let container, container.linkOpening.asksForSpace,
            let directory = BrowserSharedSpaceDirectory.read(from: container), !directory.spaces.isEmpty
        else {
            await hand(link)
            return
        }
        for space in directory.spaces {
            let iconURL = BrowserSharedSpaceDirectory.iconURL(for: space.id, in: container)
            spaceIcons[space.id] = UIImage(contentsOfFile: iconURL.path(percentEncoded: false))
        }
        selectedSpaceID = directory.initialSpaceID
        stage = .choosingSpace(link, directory)
    }

    /// Opens the link in the Space the person selected.
    func openInSelectedSpace() async {
        guard case .choosingSpace(let link, _) = stage else { return }
        stage = .working
        await hand(link.opening(in: selectedSpaceID))
    }

    func close() {
        finish()
    }

    /// Opens Crest on `link`, or saves it for Crest to open next time when
    /// the system will not open Crest from here.
    private func hand(_ link: BrowserSharedLink) async {
        if await openInCrest(link.handOffURL) {
            finish()
            return
        }
        guard let container else {
            stage = .couldNotOpen
            return
        }
        container.inbox.save(link)
        stage = .saved
    }

    // MARK: - Actions - Reading shared items

    /// The first web link among the shared items: a URL, or the first link
    /// in shared text.
    private static func sharedLink(in providers: [NSItemProvider]) async -> BrowserSharedLink? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await load(URL.self, from: provider), let link = BrowserSharedLink(url: url) {
                return link
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await load(String.self, from: provider), let link = BrowserSharedLink.firstWebLink(in: text) {
                return link
            }
        }
        return nil
    }

    private static func load<Value: _ObjectiveCBridgeable & Sendable>(
        _ type: Value.Type, from provider: NSItemProvider
    ) async -> Value? where Value._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }
}
