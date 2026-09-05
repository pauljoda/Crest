import Foundation

@MainActor
struct BrowserChromeDebuggerDocumentSnapshot {
    var document: [String: Any]
    let strings: [String]
    let frameID: String
    let nativeNodeIDs: [Int]
    let childFrameOwners: [Int]
    let weakNodeIDs: [Int]
    let contextID: Int
}

/// String indexes and node indexes belong to different tables. Remap only the
/// protocol's string columns when combining independently captured frames.
@MainActor
enum BrowserChromeDebuggerDOMSnapshotEncoding {
    static func encode(_ snapshots: [BrowserChromeDebuggerDocumentSnapshot], dom: BrowserChromeDebuggerDOM) throws
        -> [String: Any]
    {
        var strings: [String] = []
        var stringIDs: [String: Int] = [:]
        func intern(_ value: String) -> Int {
            if let id = stringIDs[value] { return id }
            let id = strings.count
            stringIDs[value] = id
            strings.append(value)
            return id
        }
        var documentIndexes: [Int: Int] = [:]
        for (index, snapshot) in snapshots.enumerated() {
            guard let root = snapshot.nativeNodeIDs.first, documentIndexes[root] == nil else {
                throw BrowserChromeDebuggerProtocolError.invalidResult
            }
            documentIndexes[root] = index
        }
        var documents: [[String: Any]] = []
        for snapshot in snapshots {
            let mapping = snapshot.strings.map(intern)
            func stringIndex(_ value: Any?) throws -> Int {
                guard let index = value as? Int, mapping.indices.contains(index) else {
                    throw BrowserChromeDebuggerProtocolError.invalidResult
                }
                return mapping[index]
            }
            func column(_ value: Any?) throws -> [Int] {
                guard let values = value as? [Int] else { throw BrowserChromeDebuggerProtocolError.invalidResult }
                return try values.map { try stringIndex($0) }
            }
            func columns(_ value: Any?) throws -> [[Int]] {
                guard let values = value as? [[Int]] else { throw BrowserChromeDebuggerProtocolError.invalidResult }
                return try values.map { try column($0) }
            }
            var document = snapshot.document
            for name in ["documentURL", "title", "baseURL", "contentLanguage", "encodingName", "publicId", "systemId"] {
                document[name] = try stringIndex(document[name])
            }
            document["frameId"] = intern(snapshot.frameID)
            guard var nodes = document["nodes"] as? [String: Any], var layout = document["layout"] as? [String: Any],
                let types = nodes["nodeType"] as? [Int], types.count == snapshot.nativeNodeIDs.count
            else { throw BrowserChromeDebuggerProtocolError.invalidResult }
            nodes["nodeName"] = try column(nodes["nodeName"])
            nodes["nodeValue"] = try column(nodes["nodeValue"])
            nodes["attributes"] = try columns(nodes["attributes"])
            guard snapshot.weakNodeIDs.count == snapshot.nativeNodeIDs.count else {
                throw BrowserChromeDebuggerProtocolError.invalidResult
            }
            nodes["backendNodeId"] = snapshot.nativeNodeIDs.indices.map { index in
                snapshot.weakNodeIDs[index] > 0
                    ? dom.weakIdentifier(snapshot.weakNodeIDs[index], contextID: snapshot.contextID)
                    : dom.identifier(snapshot.nativeNodeIDs[index])
            }
            for name in ["shadowRootType", "textValue", "inputValue", "currentSourceURL", "originURL"] {
                guard var rare = nodes[name] as? [String: Any] else { continue }
                rare["value"] = try column(rare["value"])
                nodes[name] = rare
            }
            var owners: [Int] = []
            var children: [Int] = []
            for owner in snapshot.childFrameOwners {
                guard snapshot.nativeNodeIDs.indices.contains(owner),
                    let child = dom.metadata(for: snapshot.nativeNodeIDs[owner])["contentDocument"] as? [String: Any],
                    let childID = child["nodeId"] as? Int, let index = documentIndexes[childID]
                else {
                    // A frame changed or is in a target this transport cannot
                    // inspect. Return an error rather than omit its document.
                    throw BrowserChromeDebuggerProtocolError.invalidParameter("Snapshot frame document is unavailable")
                }
                owners.append(owner)
                children.append(index)
            }
            nodes["contentDocumentIndex"] = ["index": owners, "value": children]
            layout["styles"] = try columns(layout["styles"])
            layout["text"] = try column(layout["text"])
            document["nodes"] = nodes
            document["layout"] = layout
            documents.append(document)
        }
        return ["documents": documents, "strings": strings]
    }
}
