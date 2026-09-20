import Foundation

extension BrowserStore {
    #if CREST_CORE_BACKED
    @discardableResult
    func setCoreSpaceValue<Value: Encodable>(_ operation: String, _ value: Value, in spaceID: SpaceID) -> Bool {
        do {
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
            return family.executeSpace(operation, in: spaceID, arguments: ["value": encoded], from: self)
        } catch {
            localSyncErrorDescription = "Core Space value could not be encoded: \(error)"
            return false
        }
    }

    func createCoreSpace() -> Bool {
        // Palette assets are native presentation defaults. The core assigns the
        // new Space's place and name and enforces private workspace policy.
        var template = BrowserSession.makeBlankSpace(number: session.spaces.count + 1)
        if isPrivateBrowsing { template.branding = BrowserPrivateBrowsingAppearance.branding }
        do {
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(template))
            return family.executeSpace("space.create", arguments: ["template": value], from: self)
        } catch {
            localSyncErrorDescription = "New Space could not be encoded: \(error)"
            return false
        }
    }
    #endif
}
