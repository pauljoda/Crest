import Foundation
import UniformTypeIdentifiers

/// What the Open File panel offers, and which archive format goes with the
/// engine that is actually running.
///
/// The archive entry follows the engine rather than the platform: Chromium reads
/// the MHTML it writes and cannot read a WebKit `.webarchive`, so offering both
/// would advertise a document the running engine has no reader for.
enum BrowserLocalFileOpenPolicy {
    static func contentTypes(archive: BrowserPageArchiveFormat) -> [UTType] {
        var types: [UTType] = [.html]
        if let xhtml = UTType("public.xhtml") { types.append(xhtml) }
        types.append(contentsOf: [.pdf, .plainText, .image])
        types.append(UTType(filenameExtension: archive.rawValue) ?? .data)
        return types
    }
}

extension BrowserPageArchiveFormat {
    /// The format of the engine this process registered, for the moments before a
    /// page exists to ask. The command route still prefers the active page's own
    /// engine when there is one.
    static var registered: BrowserPageArchiveFormat {
        #if CREST_CHROMIUM_HOST
        .mhtml
        #else
        .webKit
        #endif
    }
}
