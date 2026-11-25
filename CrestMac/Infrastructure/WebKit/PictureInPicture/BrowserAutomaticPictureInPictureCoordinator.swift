import Foundation

@MainActor
protocol BrowserAutomaticPictureInPictureClient: AnyObject {
    var canAutomaticallyEnterPictureInPicture: Bool { get }
    var isPictureInPictureActive: Bool { get }
    func beginAutomaticPictureInPicture(completion: @escaping @MainActor (Bool) -> Void)
    func cancelAutomaticPictureInPicture()
}

/// One reservation per application, including all windows and private Spaces.
/// Automatic requests never displace another Crest or system PiP session.
@MainActor
final class BrowserAutomaticPictureInPictureCoordinator {
    struct Trigger: Sendable {
        static let tabSwitch = Self(preference: \.automaticallyEntersPictureInPicture)
        static let appSwitch = Self(preference: \.floatsVideoOnAppSwitch)
        static let desktopSwitch = Self(preference: \.floatsVideoOnDesktopSwitch)

        fileprivate let preference: KeyPath<AppPreferences, Bool> & Sendable
    }

    static let shared = BrowserAutomaticPictureInPictureCoordinator()

    private let isEnabled: @MainActor (Trigger) -> Bool
    private let isSystemOccupied: @MainActor () -> Bool
    private let clients = NSHashTable<AnyObject>.weakObjects()
    private weak var pendingClient: (any BrowserAutomaticPictureInPictureClient)?
    private var reservation: UUID?

    init(
        isEnabled: @escaping @MainActor (Trigger) -> Bool = {
            BrowserAppPreferenceStore.shared.preferences[keyPath: $0.preference]
        },
        isSystemOccupied: @escaping @MainActor () -> Bool = { BrowserDesktopPictureInPictureAccess.isSystemOccupied() }
    ) {
        self.isEnabled = isEnabled
        self.isSystemOccupied = isSystemOccupied
    }

    func register(_ client: any BrowserAutomaticPictureInPictureClient) {
        clients.add(client)
    }

    func request(from client: any BrowserAutomaticPictureInPictureClient, for trigger: Trigger) {
        guard isEnabled(trigger), client.canAutomaticallyEnterPictureInPicture,
            pendingClient == nil,
            !clients.allObjects.contains(where: {
                ($0 as? any BrowserAutomaticPictureInPictureClient)?.isPictureInPictureActive == true
            }), !isSystemOccupied()
        else { return }
        register(client)
        let token = UUID()
        pendingClient = client
        reservation = token
        client.beginAutomaticPictureInPicture { [weak self] _ in
            guard self?.reservation == token else { return }
            self?.pendingClient = nil
            self?.reservation = nil
        }
    }

    func cancel(_ client: any BrowserAutomaticPictureInPictureClient) {
        if pendingClient === client {
            pendingClient = nil
            reservation = nil
        }
        client.cancelAutomaticPictureInPicture()
    }
}
