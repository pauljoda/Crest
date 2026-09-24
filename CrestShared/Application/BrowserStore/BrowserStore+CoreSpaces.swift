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
}
