import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

enum BrowserDeveloperCaptureError: Error {
    case pageUnavailable
    case dimensionsUnavailable
    case encodingFailed
}
