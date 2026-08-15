enum BrowserHTMLToken {
    case startTag(name: String, attributes: [String: String])
    case endTag(name: String)
    case text(String)
}
