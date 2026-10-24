import CoreGraphics
import Foundation
import Observation

/// Resolves a page's host preference against the global baseline and carries
/// it to either engine. Addresses without an HTTP(S) host keep only a
/// temporary page override.
@Observable
@MainActor
final class BrowserPageZoomSession {
    // MARK: - Variables

    private(set) var factor: CGFloat
    @ObservationIgnored var apply: @MainActor (CGFloat) -> Void = { _ in }
    @ObservationIgnored private let page: CorePage
    @ObservationIgnored private let profileID: UUID
    @ObservationIgnored private var defaultZoom: CGFloat
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var preference = SiteZoomPreference(host: nil, factor: nil)
    @ObservationIgnored private var temporaryOverride: CGFloat?

    // MARK: - Initializers

    init(page: CorePage, profileID: UUID, defaultZoom: CGFloat, url: URL?) {
        self.page = page
        self.profileID = profileID
        self.defaultZoom = BrowserDefaultPageZoomStore.normalized(defaultZoom)
        factor = self.defaultZoom
        self.url = url
        synchronize()
        page.followSiteZoom(self) { [weak self] change in
            guard let self, change.profileID == self.profileID, change.host == self.preference.host else { return }
            self.synchronize()
        }
    }

    // MARK: - Actions - Navigation

    /// Gives a page that has no document yet its first destination's zoom.
    /// Later provisional loads leave the current document's preference alone.
    func prepareForNavigation(to url: URL?) {
        guard self.url == nil, temporaryOverride == nil, let url else { return }
        self.url = url
        synchronize()
    }

    func committed(_ url: URL?) {
        self.url = url
        synchronize()
        // Engines may restore a history entry's own zoom at document commit.
        apply(factor)
    }

    private func synchronize() {
        let previousHost = preference.host
        preference = url.flatMap { page.siteZoom(for: $0) } ?? SiteZoomPreference(host: nil, factor: nil)
        if preference.host != nil || previousHost != nil { temporaryOverride = nil }
        setFactor(preference.factor.map { CGFloat($0) } ?? temporaryOverride ?? defaultZoom)
    }

    // MARK: - Actions - Zoom

    @discardableResult
    func set(_ zoom: CGFloat) -> Bool {
        let previous = factor
        if preference.host != nil, let url {
            guard page.setSiteZoom(Double(zoom), for: url) else { return false }
            synchronize()
        } else {
            temporaryOverride = zoom.matchesPageZoom(defaultZoom) ? nil : zoom
            setFactor(zoom)
        }
        return factor != previous
    }

    @discardableResult
    func reset() -> Bool {
        let previous = factor
        if preference.host != nil, let url {
            guard page.setSiteZoom(nil, for: url) else { return false }
        }
        temporaryOverride = nil
        synchronize()
        return factor != previous
    }

    @discardableResult
    func applyDefault(_ zoom: CGFloat) -> Bool {
        let previous = factor
        defaultZoom = BrowserDefaultPageZoomStore.normalized(zoom)
        if temporaryOverride?.matchesPageZoom(defaultZoom) == true { temporaryOverride = nil }
        synchronize()
        return factor != previous
    }

    private func setFactor(_ zoom: CGFloat) {
        guard factor != zoom else { return }
        factor = zoom
        apply(zoom)
    }
}
