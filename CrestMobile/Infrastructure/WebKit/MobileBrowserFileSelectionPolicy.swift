import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

enum MobileBrowserFileSelectionPolicy {
    static func contentTypes(allowsDirectories: Bool) -> [UTType] {
        allowsDirectories ? [.item, .folder] : [.item]
    }
}
