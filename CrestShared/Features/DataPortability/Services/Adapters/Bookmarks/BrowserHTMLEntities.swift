enum BrowserHTMLEntities {
    static func decode(_ source: String) -> String {
        var output = ""
        var index = source.startIndex
        while index < source.endIndex {
            guard source[index] == "&",
                let semicolon = source[index...].prefix(20).firstIndex(of: ";")
            else {
                output.append(source[index])
                index = source.index(after: index)
                continue
            }
            let nameStart = source.index(after: index)
            let name = String(source[nameStart..<semicolon])
            if let replacement = replacement(for: name) {
                output.append(replacement)
                index = source.index(after: semicolon)
            } else {
                output.append(source[index])
                index = source.index(after: index)
            }
        }
        return output
    }

    private static func replacement(for name: String) -> String? {
        switch name.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        case "nbsp": return " "
        default:
            let scalarValue: UInt32?
            if name.lowercased().hasPrefix("#x") {
                scalarValue = UInt32(name.dropFirst(2), radix: 16)
            } else if name.hasPrefix("#") {
                scalarValue = UInt32(name.dropFirst(), radix: 10)
            } else {
                scalarValue = nil
            }
            guard let scalarValue,
                let scalar = UnicodeScalar(scalarValue)
            else { return nil }
            return String(scalar)
        }
    }
}
