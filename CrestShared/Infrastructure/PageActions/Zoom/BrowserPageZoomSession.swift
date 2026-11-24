import CoreGraphics
import Foundation
import Observation

/// A page's zoom: the zoom its site keeps in the page's browsing profile,
/// which the core saves and every page of the profile showing the site
/// follows, or the device's default. The page's engine shows it through
/// `apply`. An address without an HTTP(S) host, such as a file or a blank
/// page, keeps a zoom chosen for it only while the page shows it.
@Observable
@MainActor
final class BrowserPageZoomSession {
    // MARK: - Variables

    /// The zoom the page shows.
    private(set) var factor: CGFloat
    /// Shows a zoom on the page's engine, which the page sets once it can.
    @ObservationIgnored var apply: @MainActor (CGFloat) -> Void = { _ in }
    @ObservationIgnored private let page: CorePage
    @ObservationIgnored private let profileID: UUID
    @ObservationIgnored private var defaultZoom: CGFloat
    /// The address whose site's zoom the page shows: its document's, or
    /// before its first document commits, where it is heading.
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var preference = SiteZoomPreference(host: nil, factor: nil)
    /// The zoom chosen for an address without an HTTP(S) host, while the
    /// page shows that address, `unsavedZoomURL`.
    @ObservationIgnored private var unsavedZoom: CGFloat?
    @ObservationIgnored private var unsavedZoomURL: URL?
    @ObservationIgnored private var hasCommittedDocument = false

    // MARK: - Initializers

    /// The zoom of `page`, of the profile `profileID`, showing `url`, against
    /// the device's `defaultZoom`.
    init(page: CorePage, profileID: UUID, defaultZoom: CGFloat, url: URL?) {
        self.page = page
        self.profileID = profileID
        self.defaultZoom = BrowserDefaultPageZoomStore.normalized(defaultZoom)
        factor = self.defaultZoom
        self.url = url
        synchronize()
        page.followSiteZoom(self) { [weak self] change in self?.siteZoomChanged(change) }
    }

    // MARK: - Actions - Navigation

    /// Until the page's first document commits, it shows the zoom of the site
    /// it is heading to, the latest when one load replaces another. After
    /// that, a load keeps the zoom of the document still showing until its
    /// replacement commits.
    func prepareForNavigation(to url: URL?) {
        guard !hasCommittedDocument, url != self.url else { return }
        self.url = url
        synchronize()
    }

    /// The page's document is now `url`'s, whose site's zoom it shows. The
    /// engine hears the zoom again, since one may restore the zoom a history
    /// entry had as its document commits.
    func committed(_ url: URL?) {
        hasCommittedDocument = true
        self.url = url
        synchronize()
        apply(factor)
    }

    // MARK: - Actions - Zoom

    /// Shows the page at `zoom`, which its site keeps from now on in the
    /// page's profile. Says whether the page's zoom changed.
    @discardableResult
    func set(_ zoom: CGFloat) -> Bool {
        let previous = factor
        if preference.host != nil, let url {
            // The core's change reaches every page of the site, this one too.
            guard page.setSiteZoom(Double(zoom), for: url) else { return false }
        } else {
            unsavedZoom = zoom.matchesPageZoom(defaultZoom) ? nil : zoom
            unsavedZoomURL = url
            show(zoom)
        }
        return factor != previous
    }

    /// Returns the page, and its site in the page's profile, to the device's
    /// default zoom. Says whether the page's zoom changed.
    @discardableResult
    func reset() -> Bool {
        let previous = factor
        if preference.host != nil, let url {
            guard page.setSiteZoom(nil, for: url) else { return false }
        }
        unsavedZoom = nil
        synchronize()
        return factor != previous
    }

    /// The device's default zoom is now `zoom`, which a site without a zoom
    /// of its own follows. Says whether the page's zoom changed.
    @discardableResult
    func applyDefault(_ zoom: CGFloat) -> Bool {
        let previous = factor
        defaultZoom = BrowserDefaultPageZoomStore.normalized(zoom)
        if unsavedZoom?.matchesPageZoom(defaultZoom) == true { unsavedZoom = nil }
        synchronize()
        return factor != previous
    }

    // MARK: - Actions - Following the core

    /// Reads what the site of `url` keeps from the core and shows it. A zoom
    /// chosen for an address without a host lasts only while the page shows
    /// that address.
    private func synchronize() {
        preference = url.flatMap { page.siteZoom(for: $0) } ?? SiteZoomPreference(host: nil, factor: nil)
        if preference.host != nil || url != unsavedZoomURL { unsavedZoom = nil }
        show(preference.factor.map { CGFloat($0) } ?? unsavedZoom ?? defaultZoom)
    }

    /// Another page of the profile, or this one, changed what the site this
    /// page shows keeps.
    private func siteZoomChanged(_ change: SiteZoomChanged) {
        guard change.profileID == profileID, change.host == preference.host else { return }
        preference = SiteZoomPreference(host: change.host, factor: change.factor)
        show(change.factor.map { CGFloat($0) } ?? defaultZoom)
    }

    private func show(_ zoom: CGFloat) {
        guard zoom != factor else { return }
        factor = zoom
        apply(zoom)
    }
}
