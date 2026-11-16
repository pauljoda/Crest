import AppKit
import SwiftUI

extension BrowserTabPictures {
    /// The picture of `tabID`, ready to draw, if one was kept.
    func image(of tabID: UUID) -> NSImage? {
        pictures[tabID].flatMap { NSImage(data: $0.data) }
    }

    /// The picture of `tabID` as a preview card draws it.
    func previewPicture(of tabID: UUID) -> BrowserTabPreviewPicture? {
        guard let picture = pictures[tabID], let image = NSImage(data: picture.data) else { return nil }
        return BrowserTabPreviewPicture(image: Image(nsImage: image), aspectRatio: picture.aspectRatio)
    }
}
