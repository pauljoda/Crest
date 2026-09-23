import Foundation

extension BrowserStore {
    /// Replaces one stored Space value through the core, which applies its own
    /// rules to it before accepting.
    @discardableResult
    func setCoreSpaceValue<Value: Encodable>(_ operation: BrowserSessionOperation, _ value: Value, in spaceID: SpaceID)
        -> Bool
    {
        family.executeSpace(
            operation, in: spaceID, arguments: BrowserSessionArguments.SpaceValue(value: value), from: self)
    }

    func createCoreSpace() -> Bool {
        // Palette assets are native presentation defaults. The core assigns the
        // new Space's place and name and enforces private workspace policy.
        var template = BrowserSession.makeBlankSpace(number: session.spaces.count + 1)
        if isPrivateBrowsing { template.branding = BrowserPrivateBrowsingAppearance.branding }
        return family.executeSpace(
            .spaceCreate, arguments: BrowserSessionArguments.SpaceTemplate(template: template), from: self)
    }
}
