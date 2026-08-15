import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

final class WeakMobileBrowserTransientPageLease {
    weak var value: MobileBrowserTransientPageLease?

    init(_ value: MobileBrowserTransientPageLease) {
        self.value = value
    }
}
