extension Array {
    subscript(mobileOnboardingSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
