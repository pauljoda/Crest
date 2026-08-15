import Foundation

struct BrowserCredentialSaveResult: Equatable, Sendable {
    let descriptor: CredentialDescriptor
    let disposition: BrowserCredentialSaveDisposition
}
