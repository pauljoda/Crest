enum BrowserMouseButtonPolicy {
    static func isMiddleButton(number: Int) -> Bool {
        number == 1 << 2
    }
}
