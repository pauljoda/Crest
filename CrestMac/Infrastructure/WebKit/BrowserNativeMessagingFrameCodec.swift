import Foundation
import WebKit

enum BrowserNativeMessagingFrameCodec {
    static let maximumBrowserMessageSize = 64 * 1_024 * 1_024
    static let maximumHostMessageSize = 1_024 * 1_024

    static func encode(_ value: Any) throws -> Data {
        guard
            JSONSerialization.isValidJSONObject(value)
                || value is String || value is NSNumber || value is NSNull
        else {
            throw BrowserNativeMessagingHostError.invalidMessage
        }
        let payload = try JSONSerialization.data(
            withJSONObject: value,
            options: .fragmentsAllowed
        )
        guard payload.count <= maximumBrowserMessageSize,
            payload.count <= Int(UInt32.max)
        else {
            throw BrowserNativeMessagingHostError.messageTooLarge
        }
        var length = UInt32(payload.count).littleEndian
        var framed = Data()
        withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
        framed.append(payload)
        return framed
    }
}
