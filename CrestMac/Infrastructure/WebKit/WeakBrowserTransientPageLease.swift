import Dispatch
import Foundation
import Observation
import WebKit
import os

final class WeakBrowserTransientPageLease {
    weak var value: BrowserTransientPageLease?

    init(_ value: BrowserTransientPageLease) {
        self.value = value
    }
}
