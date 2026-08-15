import Dispatch
import Foundation

/// Frames one `WKWebView.interactionState` blob with the little Crest knows
/// about it.
///
/// `interactionState` is opaque and WebKit only promises to read back a blob its
/// own build wrote, so the frame records the OS build that produced it. A blob
/// stamped by anything else is discarded rather than handed to WebKit. The frame
/// also records the URL the page was showing, which is what lets a restore be
/// declined — before WebKit is touched at all — when the tab has since been
/// pointed somewhere else.
struct BrowserTabStateEnvelope: Equatable, Sendable {
    /// Crest's own framing version, bumped when this layout changes. It is not
    /// WebKit's: the OS build covers that.
    static let currentFormatVersion: UInt16 = 1
    private static let magic = Data("CRTS".utf8)
    private static let headerByteCount = 12

    let formatVersion: UInt16
    let osBuild: String
    let url: URL?
    let interactionState: Data

    /// The OS build this process is running against. Apple ships WebKit in
    /// lockstep with the system, so the system build identifies the writer.
    static var currentOSBuild: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    init(
        interactionState: Data,
        url: URL?,
        formatVersion: UInt16 = BrowserTabStateEnvelope.currentFormatVersion,
        osBuild: String = BrowserTabStateEnvelope.currentOSBuild
    ) {
        self.interactionState = interactionState
        self.url = url
        self.formatVersion = formatVersion
        self.osBuild = osBuild
    }

    /// True when this build of Crest, on this OS build, may hand the payload to
    /// WebKit. Everything else is treated as absent state.
    var isRestorable: Bool {
        formatVersion == Self.currentFormatVersion && osBuild == Self.currentOSBuild
    }

    func encoded() -> Data {
        let osBuildBytes = Data(osBuild.utf8)
        let urlBytes = Data((url?.absoluteString ?? "").utf8)
        var encoded = Data(
            capacity: Self.headerByteCount + osBuildBytes.count
                + urlBytes.count + interactionState.count)
        encoded.append(Self.magic)
        encoded.append(Self.littleEndianBytes(formatVersion))
        encoded.append(Self.littleEndianBytes(UInt16(clamping: osBuildBytes.count)))
        encoded.append(Self.littleEndianBytes(UInt32(clamping: urlBytes.count)))
        encoded.append(osBuildBytes)
        encoded.append(urlBytes)
        encoded.append(interactionState)
        return encoded
    }

    static func decode(_ data: Data) -> Self? {
        guard data.count >= headerByteCount,
            data.prefix(magic.count) == magic,
            let formatVersion = readUInt16(data, at: 4),
            let osBuildByteCount = readUInt16(data, at: 6).map(Int.init),
            let urlByteCount = readUInt32(data, at: 8).map(Int.init)
        else {
            return nil
        }
        let osBuildStart = data.startIndex + headerByteCount
        let urlStart = osBuildStart + osBuildByteCount
        let payloadStart = urlStart + urlByteCount
        guard payloadStart <= data.endIndex,
            let osBuild = String(data: data[osBuildStart..<urlStart], encoding: .utf8),
            let address = String(data: data[urlStart..<payloadStart], encoding: .utf8)
        else {
            return nil
        }
        return Self(
            interactionState: Data(data[payloadStart..<data.endIndex]),
            url: address.isEmpty ? nil : URL(string: address),
            formatVersion: formatVersion,
            osBuild: osBuild
        )
    }

    private static func littleEndianBytes(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func littleEndianBytes(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard data.count >= offset + 2 else { return nil }
        let start = data.startIndex + offset
        return UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard data.count >= offset + 4 else { return nil }
        let start = data.startIndex + offset
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }
}
