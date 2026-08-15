import SwiftUI

enum MobileRegularBrowserBackdropPolicy {
    static let rootOwnsAtmosphere = true
    static let atmosphereSafeAreaEdges: Edge.Set = .all
    static let extendsBehindTopSafeArea = atmosphereSafeAreaEdges.contains(.top)
}
