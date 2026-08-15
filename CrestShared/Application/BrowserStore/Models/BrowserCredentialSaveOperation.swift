import Foundation

struct BrowserCredentialSaveOperation {
    let id: UUID
    let completion: Task<Void, Never>
}
