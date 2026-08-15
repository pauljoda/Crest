import Foundation

/// The host notification center, reduced to the surface Crest's emulated
/// `chrome.notifications` needs.
///
/// The seam is deliberately framework-neutral so the routing rules that decide
/// *which* extension owns a notification stay in the Application layer and stay
/// testable without a real notification center. Platform adapters translate
/// deliveries into their own request types and translate interactions back into
/// ``BrowserExtensionNotificationSystemEvent``.
@MainActor
protocol BrowserExtensionNotificationCentering: AnyObject {
    /// The current authorization state without prompting.
    func currentAuthorization() async -> BrowserExtensionNotificationAuthorization

    /// Prompts when the state is undetermined, then reports the settled state.
    func requestAuthorization() async -> BrowserExtensionNotificationAuthorization

    /// Presents `delivery`, throwing when the host rejects it.
    func add(_ delivery: BrowserExtensionNotificationDelivery) async throws

    /// Withdraws the named notifications, ignoring identifiers that are not
    /// currently presented.
    func removeDelivered(systemIdentifiers: [String]) async

    /// The system identifiers this process currently has on screen, in the
    /// host's own order.
    func deliveredSystemIdentifiers() async -> [String]

    /// Installs the single sink that receives every interaction. Calling this
    /// again replaces the previous sink.
    func setEventHandler(
        _ handler: @escaping @MainActor (BrowserExtensionNotificationSystemEvent) -> Void
    )
}
