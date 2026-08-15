import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

enum MobileLinkPeekPressPhase: Equatable {
    case idle
    case pressing
    case staged
    case committed
}
