import AppKit
import Foundation
import WebKit

struct BrowserExtensionWebpageNativeMenuItem {
    let definition: BrowserExtensionWebpageMenuDefinition
    let nativeItem: NSMenuItem
    let children: [BrowserExtensionWebpageNativeMenuItem]
}

enum BrowserExtensionWebpageMenuMappingError: Error, Equatable {
    case invalidDefinitionTree
    case nativeTreeMismatch
}

@MainActor
enum BrowserExtensionWebpageMenuPolicy {
    static func matchingDefinitions(
        _ definitions: [BrowserExtensionWebpageMenuDefinition],
        context: BrowserExtensionWebpageMenuContext
    ) -> [BrowserExtensionWebpageMenuDefinition] {
        definitions.filter { definition in
            matches(definition, context: context)
        }
    }

    static func title(
        for definition: BrowserExtensionWebpageMenuDefinition,
        context: BrowserExtensionWebpageMenuContext
    ) -> String {
        definition.title.replacingOccurrences(
            of: "%s",
            with: context.selectionText ?? ""
        )
    }

    static func nativeItems(
        _ nativeItems: [NSMenuItem],
        definitions: [BrowserExtensionWebpageMenuDefinition]
    ) throws -> [BrowserExtensionWebpageNativeMenuItem] {
        let ids = definitions.map(\.id)
        guard Set(ids).count == ids.count else {
            throw BrowserExtensionWebpageMenuMappingError.invalidDefinitionTree
        }
        let definitionsByParent = Dictionary(
            grouping: definitions,
            by: \.parentID
        )
        for definition in definitions {
            if let parentID = definition.parentID,
                !ids.contains(parentID)
            {
                throw BrowserExtensionWebpageMenuMappingError
                    .invalidDefinitionTree
            }
        }
        let rootDefinitions = definitionsByParent[nil] ?? []
        let rootNativeItems: [NSMenuItem]
        if nativeItems.count == 1,
            rootDefinitions.count > 1,
            let groupedItems = nativeItems[0].submenu?.items,
            groupedItems.count == rootDefinitions.count
        {
            rootNativeItems = groupedItems
        } else {
            rootNativeItems = nativeItems
        }
        return try map(
            rootNativeItems,
            definitions: rootDefinitions,
            definitionsByParent: definitionsByParent
        )
    }

    static func tabItems(
        _ nativeItems: [NSMenuItem],
        definitions: [BrowserExtensionWebpageMenuDefinition],
        pageURL: URL?
    ) throws -> [NSMenuItem] {
        try Self.nativeItems(
            nativeItems,
            definitions: definitions
        ).compactMap {
            tabItem(from: $0, pageURL: pageURL)
        }
    }

    private static func matches(
        _ definition: BrowserExtensionWebpageMenuDefinition,
        context: BrowserExtensionWebpageMenuContext
    ) -> Bool {
        guard definition.visible else { return false }
        guard
            definition.contexts.contains("all")
                || !definition.contexts.isDisjoint(
                    with: context.declaredContexts
                )
        else { return false }
        guard
            patterns(
                definition.documentURLPatterns,
                match: context.documentURL
            )
        else { return false }
        guard
            definition.targetURLPatterns.isEmpty
                || patterns(
                    definition.targetURLPatterns,
                    match: context.targetURL
                )
        else { return false }
        return true
    }

    private static func tabItem(
        from mapped: BrowserExtensionWebpageNativeMenuItem,
        pageURL: URL?
    ) -> NSMenuItem? {
        let definition = mapped.definition
        let matchesTab =
            definition.visible
            && (definition.contexts.contains("all")
                || definition.contexts.contains("tab"))
            && patterns(definition.documentURLPatterns, match: pageURL)
            && definition.targetURLPatterns.isEmpty
        let children = mapped.children.compactMap {
            tabItem(from: $0, pageURL: pageURL)
        }
        guard matchesTab || !children.isEmpty,
            let clone = mapped.nativeItem.copy() as? NSMenuItem
        else { return nil }
        if mapped.children.isEmpty {
            clone.submenu = nil
        } else {
            let submenu = NSMenu(title: clone.title)
            submenu.items = children
            clone.submenu = submenu
        }
        if matchesTab {
            clone.isEnabled =
                definition.enabled
                && mapped.nativeItem.isEnabled
        } else {
            clone.target = nil
            clone.action = nil
        }
        return clone
    }

    /// Whether an authored pattern list admits `url`.
    ///
    /// Only an *absent* list is unrestricted. A list the extension authored
    /// restricts the item to what it names, so a pattern WebKit cannot parse
    /// admits nothing rather than everything: an item whose every pattern is
    /// unsupported never appears. The compatibility runtime forwards authored
    /// patterns whole precisely so this distinction survives — filtering them
    /// there turned "only this site" into "every site".
    private static func patterns(
        _ patterns: [String],
        match url: URL?
    ) -> Bool {
        guard !patterns.isEmpty else { return true }
        guard let url else { return false }
        return patterns.contains { pattern in
            guard
                let matchPattern = try? WKWebExtension.MatchPattern(
                    string: pattern
                )
            else { return false }
            return matchPattern.matches(url)
        }
    }

    private static func map(
        _ nativeItems: [NSMenuItem],
        definitions: [BrowserExtensionWebpageMenuDefinition],
        definitionsByParent: [String?: [BrowserExtensionWebpageMenuDefinition]]
    ) throws -> [BrowserExtensionWebpageNativeMenuItem] {
        guard nativeItems.count == definitions.count else {
            throw BrowserExtensionWebpageMenuMappingError.nativeTreeMismatch
        }
        return try zip(nativeItems, definitions).map { nativeItem, definition in
            let childDefinitions = definitionsByParent[definition.id] ?? []
            let nativeChildren = nativeItem.submenu?.items ?? []
            let children = try map(
                nativeChildren,
                definitions: childDefinitions,
                definitionsByParent: definitionsByParent
            )
            guard
                (definition.type == .separator)
                    == nativeItem.isSeparatorItem
            else {
                throw BrowserExtensionWebpageMenuMappingError
                    .nativeTreeMismatch
            }
            return BrowserExtensionWebpageNativeMenuItem(
                definition: definition,
                nativeItem: nativeItem,
                children: children
            )
        }
    }
}
