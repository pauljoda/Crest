import Foundation

extension CoreState {
    // MARK: - Actions - Content blocking

    /// How every page blocks ads and trackers: the device's level decides, the
    /// same in every Space. A Space's own policy no longer counts.
    var contentBlockingPolicy: ContentBlockingPolicy {
        filterLists.level.blocksContent ? .balanced : .off
    }
}
