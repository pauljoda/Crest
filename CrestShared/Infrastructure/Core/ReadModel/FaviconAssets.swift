import Foundation
import Observation

/// The images tabs wear, by tab. The bytes are native assets the core never
/// sees: it records only which tab wears which image. The issuer of a command
/// offers the images it holds, and each session change places, keeps, copies
/// or drops them by the rules its record documents. Each tab's image is
/// observed on its own, so a new favicon redraws only its tab, and each is
/// stored before it is announced; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class FaviconAssets {
    // MARK: - Types

    /// The images the issuer of a command holds: `assigned` for the tab the
    /// core tells to adopt the image its page reported, `placed`, by tab, for
    /// the tabs the command places that had none, and `imported`, by the
    /// position of each Space an import brings, the images of that Space's
    /// tabs, open or archived.
    struct Offer {
        var assigned: Data?
        var placed: [UUID: Data] = [:]
        var imported: [[UUID: Data]] = []
    }

    /// One tab's image, observed on its own.
    @MainActor
    @Observable
    fileprivate final class Slot: BrowserStoreFirstObservable {
        var data: Data? {
            get { observed(\.dataStorage, as: \.data) }
            set { publish(newValue, into: \.dataStorage, as: \.data) }
        }
        @ObservationIgnored private var dataStorage: Data?

        init(data: Data?) {
            dataStorage = data
        }
    }

    // MARK: - Variables

    @ObservationIgnored private var slots: [UUID: Slot] = [:]
    /// The offer of the command whose changes are being applied, by workspace.
    @ObservationIgnored private var offers: [UUID: Offer] = [:]
    /// Tabs a change of the batch being applied removed, whose images stay
    /// for a later change that places them again.
    @ObservationIgnored private var detached: Set<UUID> = []
    /// Counts the tabs that gained an image without a slot of their own, so
    /// the readers of a tab the read model does not hold yet hear when it
    /// gains one. Every tab a change places gets a slot, even an empty one,
    /// so a tab the read model holds is observed through its slot alone and
    /// an image another tab gains never redraws it.
    private var additions: Int {
        get { observed(\.additionsStorage, as: \.additions) }
        set { publish(newValue, into: \.additionsStorage, as: \.additions) }
    }
    @ObservationIgnored private var additionsStorage = 0
    /// Hands over the image a page reported, which leaves the store that kept
    /// it until a tab adopted it.
    @ObservationIgnored var takePageImage: (UUID) -> Data? = { _ in nil }

    // MARK: - Actions - Reading

    /// The image the tab wears, or nil when it wears none.
    func image(of tabID: UUID) -> Data? {
        guard let slot = slots[tabID] else {
            _ = additions
            return nil
        }
        return slot.data
    }

    // MARK: - Actions - Offers

    /// Holds the images the issuer of a command in `workspaceID` offers until
    /// it withdraws them, once the core's changes for the command are applied.
    func offer(_ offer: Offer, in workspaceID: UUID) {
        offers[workspaceID] = offer
    }

    func withdrawOffer(in workspaceID: UUID) {
        offers[workspaceID] = nil
    }

    // MARK: - Actions - Changes

    /// Tabs a change placed where they were not before: each keeps the image
    /// it wore, even one a change earlier in the batch removed, and a tab that
    /// wore none takes the one the issuer offered, or an empty slot.
    func place(_ tabIDs: some Sequence<UUID>, in workspaceID: UUID) {
        let offer = offers[workspaceID]
        for tabID in tabIDs {
            detached.remove(tabID)
            guard slots[tabID]?.data == nil else { continue }
            setImage(offer?.placed[tabID], of: tabID)
        }
    }

    /// Images the platform kept before its session reached the read model,
    /// such as the ones a launch reads from disk: each tab `holds` names that
    /// wears none takes its own.
    func adopt(_ images: [UUID: Data], holding holds: (UUID) -> Bool) {
        for (tabID, data) in images where slots[tabID]?.data == nil && holds(tabID) {
            setImage(data, of: tabID)
        }
    }

    /// Tabs a change removed keep their images until the batch ends.
    func detach(_ tabIDs: some Sequence<UUID>) {
        detached.formUnion(tabIDs)
    }

    /// A copy shows the image its source wears, or the one offered for it.
    func copy(_ sourceTabID: UUID, to copyTabID: UUID, in workspaceID: UUID) {
        setImage(slots[sourceTabID]?.data ?? offers[workspaceID]?.placed[sourceTabID], of: copyTabID)
    }

    /// Each tab an import placed wears the image its issuer offered for the
    /// tab it came from. Every image is read before any is set.
    func place(imported tabs: [ImportedTab], in workspaceID: UUID) {
        let offered = offers[workspaceID]?.imported ?? []
        let images = tabs.map { tab in
            (tab.tabID, offered.indices.contains(tab.source) ? offered[tab.source][tab.sourceTabID] : nil)
        }
        for (tabID, image) in images {
            detached.remove(tabID)
            setImage(image, of: tabID)
        }
    }

    /// A tab told to adopt an image wears the one `pageID` reported, which
    /// moves here from the page's store, or with no page the one its command's
    /// issuer offered, and keeps its own when neither holds one; one told not
    /// to adopt wears none.
    func assign(adopts: Bool, to tabID: UUID, in workspaceID: UUID, from pageID: UUID?) {
        guard adopts else {
            setImage(nil, of: tabID)
            return
        }
        let offered = if let pageID { takePageImage(pageID) } else { offers[workspaceID]?.assigned }
        if let offered { setImage(offered, of: tabID) }
    }

    /// The batch ended: a removed tab that `holds` says no workspace holds
    /// any longer loses its image.
    func finishBatch(holding holds: (UUID) -> Bool) {
        for tabID in detached where !holds(tabID) {
            slots.removeValue(forKey: tabID)?.data = nil
        }
        detached.removeAll()
    }

    private func setImage(_ data: Data?, of tabID: UUID) {
        if let slot = slots[tabID] {
            slot.data = data
        } else {
            slots[tabID] = Slot(data: data)
            if data != nil { additions &+= 1 }
        }
    }
}

extension FaviconAssets: BrowserStoreFirstObservable {}
