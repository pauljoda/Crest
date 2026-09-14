import Foundation

/// Arc's source structure, before bookmark or session import policies are applied.
struct ArcSidebarDocument {
    let containers: [Container]

    init?(data: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let sidebar = root["sidebar"] as? [String: Any],
            let rawContainers = sidebar["containers"] as? [Any]
        else { return nil }
        containers = rawContainers.compactMap { raw in
            (raw as? [String: Any]).map(Container.init)
        }
    }

    struct Container {
        // Keep ordered entries: each importer owns its existing duplicate-ID policy.
        let items: [Item]
        let spaces: [Space]
        let favoriteContainerIDs: [String: String]

        fileprivate init(_ source: [String: Any]) {
            items = alternatingObjects(source["items"]).map(Item.init)
            spaces = alternatingObjects(source["spaces"]).map(Space.init)
            var favorites: [String: String] = [:]
            let values = source["topAppsContainerIDs"] as? [Any] ?? []
            var index = 0
            while index + 1 < values.count {
                if let id = values[index + 1] as? String {
                    favorites[profileKey(values[index])] = id
                }
                index += 2
            }
            favoriteContainerIDs = favorites
        }
    }

    struct Space {
        let title: String?
        let containerIDs: [String]
        let newContainerIDs: [String]
        let profileKey: String
        let customInfo: [String: Any]?

        fileprivate init(_ source: [String: Any]) {
            title = source["title"] as? String
            containerIDs = stringValues(source["containerIDs"])
            newContainerIDs = stringValues(source["newContainerIDs"])
            profileKey = ArcSidebarDocument.profileKey(source["profile"])
            customInfo = source["customInfo"] as? [String: Any]
        }
    }

    struct Item {
        let id: String?
        let title: String?
        let childrenIDs: [String]
        let content: Content?

        fileprivate init(_ source: [String: Any]) {
            id = source["id"] as? String
            title = source["title"] as? String
            childrenIDs = stringValues(source["childrenIds"])
            content = (source["data"] as? [String: Any]).map { data in
                Content(
                    tab: (data["tab"] as? [String: Any]).map { tab in
                        Tab(
                            title: tab["savedTitle"] as? String ?? source["title"] as? String ?? "",
                            url: tab["savedURL"] as? String,
                            lastActivatedAtValue: tab["timeLastActiveAt"] ?? source["createdAt"]
                        )
                    },
                    isFolder: data["list"] is [String: Any]
                )
            }
        }
    }

    struct Content {
        let tab: Tab?
        let isFolder: Bool
    }

    struct Tab {
        let title: String
        let url: String?
        // Bookmark and session imports intentionally interpret date scalars differently.
        let lastActivatedAtValue: Any?
    }

    private static func alternatingObjects(_ value: Any?) -> [[String: Any]] {
        if let array = value as? [Any] {
            var result: [[String: Any]] = []
            var pendingID: String?
            for value in array {
                if let id = value as? String {
                    pendingID = id
                } else if var object = value as? [String: Any] {
                    if object["id"] == nil { object["id"] = pendingID }
                    result.append(object)
                    pendingID = nil
                }
            }
            return result
        }
        guard let dictionary = value as? [String: Any] else { return [] }
        return dictionary.compactMap { id, raw in
            guard var object = raw as? [String: Any] else { return nil }
            if object["id"] == nil { object["id"] = id }
            return object
        }
    }

    private static func stringValues(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func profileKey(_ value: Any?) -> String {
        guard let dictionary = value as? [String: Any] else { return "unknown" }
        if (dictionary["default"] as? NSNumber)?.boolValue == true {
            return "default"
        }
        let custom = dictionary["custom"] as? [String: Any]
        let details = custom?["_0"] as? [String: Any]
        let machine = details?["machineID"] as? String ?? ""
        let directory = details?["directoryBasename"] as? String ?? ""
        return "custom:\(machine):\(directory)"
    }
}
