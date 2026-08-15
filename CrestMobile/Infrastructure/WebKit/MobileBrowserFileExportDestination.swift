import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

enum MobileBrowserFileExportDestination: CaseIterable, Equatable, Identifiable, Sendable {
    case share
    case files

    var id: Self { self }

    var title: String {
        switch self {
        case .share:
            "Share…"
        case .files:
            "Save to Files…"
        }
    }

    var systemImage: String {
        switch self {
        case .share:
            "square.and.arrow.up"
        case .files:
            "folder.badge.plus"
        }
    }
}
