import SwiftUI
import UIKit

extension BrowserTabPictures {
    /// The picture of `tabID` as a preview card draws it.
    func previewPicture(of tabID: UUID) -> BrowserTabPreviewPicture? {
        guard let picture = pictures[tabID], let image = UIImage(data: picture.data) else { return nil }
        return BrowserTabPreviewPicture(image: Image(uiImage: image), aspectRatio: picture.aspectRatio)
    }
}
