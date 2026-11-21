import SwiftUI

/// Hands the identity of the window a reader view is in to a binding, only
/// when it changes. Each platform's `BrowserDownloadFeedbackWindowIdentityReader`
/// reports its window through one.
final class BrowserWindowIdentityCoordinator {
    // MARK: - Variables

    var identifier: Binding<ObjectIdentifier?>

    // MARK: - Initializers

    init(identifier: Binding<ObjectIdentifier?>) {
        self.identifier = identifier
    }

    // MARK: - Mutators

    func set(_ value: ObjectIdentifier?) {
        guard identifier.wrappedValue != value else { return }
        identifier.wrappedValue = value
    }
}
