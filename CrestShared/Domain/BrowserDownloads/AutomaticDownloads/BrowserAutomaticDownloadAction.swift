/// Raw values are the core's `downloads.automatic` spellings.
enum BrowserAutomaticDownloadAction: String, Decodable, Equatable {
    case allow
    case deny
    case requestPermission
}
