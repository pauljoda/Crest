import CoreGraphics

enum BrowserMainWindowSizingPolicy {
    static let permitsUserResizing = true
    static let minimumContentSize = CGSize(width: 900, height: 600)
    static let idealContentSize = CGSize(width: 1440, height: 900)
}
