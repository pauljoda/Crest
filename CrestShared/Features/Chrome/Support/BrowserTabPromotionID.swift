enum BrowserTabPromotionID {
    static func value(for tabID: TabID) -> String {
        "crest-tab-promotion-\(tabID)"
    }
}
