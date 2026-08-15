import Foundation

struct BrowserEncryptedPasswordRecord {
    let origin: CredentialOrigin
    let username: String
    let encryptedPassword: Data
}
