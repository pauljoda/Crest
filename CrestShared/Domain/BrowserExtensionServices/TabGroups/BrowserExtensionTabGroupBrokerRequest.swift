import Foundation

/// Failures the tab-group broker reports to an extension.
///
/// The text is Chromium's, verbatim, from
/// `chrome/common/extensions/api/tab_groups_api.cc` and `ExtensionTabUtil`:
/// portable packages branch on these strings, and inventing Crest-flavoured
/// wording is what turns a handled error into an unhandled one.
enum BrowserExtensionTabGroupBrokerError: LocalizedError, Equatable {
    case invalidRequest
    /// `kUnableToFindTabError`. The wire target named a tab index the Space no
    /// longer has, or whose URL changed since JavaScript resolved it.
    case staleTab
    /// `ExtensionTabUtil::kGroupNotFoundError`.
    case unknownGroup(Int)
    /// `kFailedToMoveGroupError`. Crest does not reorder tabs for a group, so
    /// every `tabGroups.move` ends here — after the group id is validated, so
    /// a bad id still reports the bad id.
    case failedToMove
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The extension supplied an invalid tab group request."
        case .staleTab: "Unable to find tab."
        case .unknownGroup(let id): "No group with id: \(id)."
        case .failedToMove: "Failed to move group."
        case .unavailable: "Crest's tab group registry is unavailable."
        }
    }
}

/// Chromium matches `tabGroups.query`'s `title` with `base::MatchPattern`.
///
/// That is a glob, not a regular expression: `*` spans any run of characters
/// and `?` stands for exactly one. Implemented here so the rule is testable
/// without a broker, a WebView, or a Space.
enum BrowserExtensionTabGroupTitlePattern {
    static func matches(_ value: String, pattern: String) -> Bool {
        matches(Array(value), Array(pattern))
    }

    private static func matches(
        _ value: [Character], _ pattern: [Character]
    ) -> Bool {
        // Iterative backtracking: `star` remembers the last `*` so a failed
        // suffix retries one character later instead of recursing per branch.
        var valueIndex = 0
        var patternIndex = 0
        var starIndex: Int?
        var resumeIndex = 0
        while valueIndex < value.count {
            if patternIndex < pattern.count,
                pattern[patternIndex] == "?" || pattern[patternIndex] == value[valueIndex]
            {
                valueIndex += 1
                patternIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                resumeIndex = valueIndex
                patternIndex += 1
            } else if let starIndex {
                patternIndex = starIndex + 1
                resumeIndex += 1
                valueIndex = resumeIndex
            } else {
                return false
            }
        }
        while patternIndex < pattern.count, pattern[patternIndex] == "*" { patternIndex += 1 }
        return patternIndex == pattern.count
    }
}

/// The decoded wire request behind one `tabGroups.*`, `tabs.group`, or
/// `tabs.ungroup` call.
///
/// Like the sidebar broker, the wire carries no invented WebKit identifier:
/// JavaScript resolves a numeric tab id through the native `tabs.get` and
/// sends back the primary window's tab index plus the URL it saw, and this
/// decoder re-checks both against the live Space before a tab is accepted.
/// Group ids are Crest's own registry ids, which no other surface publishes.
struct BrowserExtensionTabGroupBrokerRequest {
    enum Operation: String, CaseIterable, Sendable {
        case get = "tabGroups.get"
        case query = "tabGroups.query"
        case update = "tabGroups.update"
        case move = "tabGroups.move"
        /// The `Tab.groupId` mirror. Gated on `tabs`, not `tabGroups`: Chrome
        /// puts `groupId` on every tab object a package with `tabs` can see.
        case membership = "tabGroups.membership"
        case group = "tabs.group"
        case ungroup = "tabs.ungroup"
    }

    struct TabTarget: Equatable, Sendable {
        let index: Int
        let url: String?
    }

    struct QueryFilter: Equatable, Sendable {
        var isCollapsed: Bool?
        var color: String?
        var title: String?
        var isShared: Bool?

        func matches(_ group: BrowserExtensionTabGroup) -> Bool {
            if let isCollapsed, isCollapsed != group.isCollapsed { return false }
            if let color, color != group.color.rawValue { return false }
            // Chrome's groups are never shared in Crest, so a `shared: true`
            // filter matches nothing rather than everything.
            if let isShared, isShared { return false }
            if let title {
                guard
                    BrowserExtensionTabGroupTitlePattern.matches(
                        group.title ?? "", pattern: title)
                else { return false }
            }
            return true
        }
    }

    let operation: Operation
    let groupID: Int?
    let targets: [TabTarget]
    let filter: QueryFilter
    let title: String?
    let color: BrowserExtensionTabGroupColor?
    let isCollapsed: Bool?

    /// `tabGroups.*` are gated on the namespace's own permission. Grouping is
    /// part of `chrome.tabs` in Chromium's schema and gated with it here.
    var requiredCapability: String {
        switch operation {
        case .get, .query, .update, .move: "tabGroups"
        case .membership, .group, .ungroup: "tabs"
        }
    }

    init(message: [String: Any]) throws {
        guard let api = message["api"] as? String, let operation = Operation(rawValue: api) else {
            throw BrowserExtensionTabGroupBrokerError.invalidRequest
        }
        self.operation = operation
        title = try Self.string(message, "title")
        isCollapsed = try Self.boolean(message, "collapsed")
        if let rawColor = try Self.string(message, "color") {
            guard let color = BrowserExtensionTabGroupColor(rawValue: rawColor) else {
                throw BrowserExtensionTabGroupBrokerError.invalidRequest
            }
            self.color = color
        } else {
            color = nil
        }

        switch operation {
        case .get, .update, .move:
            groupID = try Self.integer(message, "groupId", required: true)
            targets = []
            filter = .init()
        case .query:
            groupID = nil
            targets = []
            filter = QueryFilter(
                isCollapsed: isCollapsed,
                color: color?.rawValue,
                title: title,
                isShared: try Self.boolean(message, "shared")
            )
        case .membership:
            groupID = nil
            targets = []
            filter = .init()
        case .group, .ungroup:
            groupID = try Self.integer(message, "groupId", required: false)
            guard let rawTargets = message["tabs"] as? [[String: Any]], !rawTargets.isEmpty else {
                throw BrowserExtensionTabGroupBrokerError.invalidRequest
            }
            targets = try rawTargets.map(Self.target)
            filter = .init()
        }
    }

    /// Re-verifies every wire target against the live Space.
    ///
    /// A transient page — a Peek — is announced to extensions but is not a
    /// session tab, so it cannot be grouped: `liveTabs` excludes it and the
    /// lookup fails the same way a closed tab does.
    func resolveTabs(
        in space: BrowserExtensionSpaceState, liveTabs: Set<TabID>
    ) throws -> [TabID] {
        try targets.map { target in
            guard let tab = space.tabs.first(where: { $0.index == target.index }),
                liveTabs.contains(tab.id),
                target.url == nil || tab.url?.absoluteString == target.url
            else { throw BrowserExtensionTabGroupBrokerError.staleTab }
            return tab.id
        }
    }

    private static func target(_ value: [String: Any]) throws -> TabTarget {
        guard let index = try integer(value, "tabIndex", required: true), index >= 0 else {
            throw BrowserExtensionTabGroupBrokerError.invalidRequest
        }
        return TabTarget(index: index, url: try string(value, "url"))
    }

    private static func integer(
        _ value: [String: Any], _ key: String, required: Bool
    ) throws -> Int? {
        guard let raw = value[key] else {
            guard required else { return nil }
            throw BrowserExtensionTabGroupBrokerError.invalidRequest
        }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
            number.doubleValue >= Double(Int32.min), number.doubleValue <= Double(Int32.max)
        else { throw BrowserExtensionTabGroupBrokerError.invalidRequest }
        return number.intValue
    }

    private static func string(_ value: [String: Any], _ key: String) throws -> String? {
        guard let raw = value[key] else { return nil }
        guard let result = raw as? String else {
            throw BrowserExtensionTabGroupBrokerError.invalidRequest
        }
        return result
    }

    private static func boolean(_ value: [String: Any], _ key: String) throws -> Bool? {
        guard let raw = value[key] else { return nil }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw BrowserExtensionTabGroupBrokerError.invalidRequest
        }
        return number.boolValue
    }
}
