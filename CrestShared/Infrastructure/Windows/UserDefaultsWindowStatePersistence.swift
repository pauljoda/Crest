import Dispatch
import Foundation

final class UserDefaultsBrowserWindowStatePersistence:
    BrowserWindowStatePersisting,
    @unchecked Sendable
{
    /// How many windows may keep a restoration record.
    ///
    /// The stored set has to limit itself. macOS restores one shell under a fixed
    /// identity, but every unrestored iOS scene comes back with a fresh random
    /// `BrowserWindowID`, so each force-quit would otherwise leave a record behind
    /// forever — nothing in the app removes one. This is comfortably more windows
    /// than iPadOS will show at once, and a Mac only ever occupies one slot.
    static let maximumStoredStateCount = 16

    private let defaults: UserDefaults
    private let key: String
    private let maximumStoredStateCount: Int
    private let encoder: @Sendable ([BrowserWindowState]) -> Data?
    private let publisher: @Sendable (UserDefaults, String, Data) -> Void
    private let saveQueue: DispatchQueue
    private var latestEncodedData: Data?

    init(
        defaults: UserDefaults = .standard,
        key: String = "crest.windows.v1",
        maximumStoredStateCount: Int = UserDefaultsBrowserWindowStatePersistence
            .maximumStoredStateCount,
        encoder: @escaping @Sendable ([BrowserWindowState]) -> Data? = {
            try? JSONEncoder().encode($0)
        },
        publisher: @escaping @Sendable (UserDefaults, String, Data) -> Void = {
            defaults,
            key,
            data in
            defaults.set(data, forKey: key)
        }
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumStoredStateCount = max(1, maximumStoredStateCount)
        self.encoder = encoder
        self.publisher = publisher
        saveQueue = DispatchQueue(
            label: "com.pauldavis.crest.window-state-persistence",
            qos: .utility
        )
    }

    func load(id: BrowserWindowID) -> BrowserWindowState? {
        saveQueue.sync {
            decodedStates().first { $0.id == id }
        }
    }

    /// Stores one window's state, newest last.
    ///
    /// The record moves to the end of the list even when it already existed, which
    /// is what makes the list an order of last use and lets the cap evict the
    /// window nobody has touched in the longest time. Order is otherwise
    /// meaningless: `load(id:)` looks a window up by identity.
    func save(_ state: BrowserWindowState) {
        updateStates { [maximumStoredStateCount] states in
            states.removeAll { $0.id == state.id }
            states.append(state)
            if states.count > maximumStoredStateCount {
                states.removeFirst(states.count - maximumStoredStateCount)
            }
        }
    }

    func remove(id: BrowserWindowID) {
        updateStates { states in
            states.removeAll { $0.id == id }
        }
    }

    func flushPendingSaves() async {
        await withCheckedContinuation { continuation in
            saveQueue.async {
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }

    private func updateStates(
        _ update: @escaping @Sendable (inout [BrowserWindowState]) -> Void
    ) {
        saveQueue.async { [self] in
            var states = decodedStates()
            update(&states)
            guard let data = encoder(states) else { return }
            latestEncodedData = data
            DispatchQueue.main.async { [self] in
                publisher(defaults, key, data)
            }
        }
    }

    private func decodedStates() -> [BrowserWindowState] {
        let data = latestEncodedData ?? defaults.data(forKey: key)
        guard let data else { return [] }
        return (try? JSONDecoder().decode([BrowserWindowState].self, from: data)) ?? []
    }
}
