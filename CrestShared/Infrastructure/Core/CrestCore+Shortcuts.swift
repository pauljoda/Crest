import Foundation

extension CrestCore {
    /// Where each numbered command leads when a window shows `tabCount` tabs
    /// in sidebar order and there are `spaceCount` Spaces. A command with
    /// nowhere to go is absent.
    func numberedSelections(tabCount: Int, spaceCount: Int) -> [ShortcutCommand: NumberedSelection] {
        let question = NumberedSelections(tabCount: tabCount, spaceCount: spaceCount)
        guard let answer = try? query(question) else { return [:] }
        return Dictionary(answer.selections.map { ($0.command, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
