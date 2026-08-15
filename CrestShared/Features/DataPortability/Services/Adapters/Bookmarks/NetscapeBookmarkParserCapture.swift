enum NetscapeBookmarkParserCapture {
    case folder(attributes: [String: String], text: String)
    case bookmark(attributes: [String: String], text: String)
}
