import Foundation

struct BrowserSetupSiteSuggestion: Identifiable, Equatable, Sendable {
    let title: String
    let url: URL
    let systemImage: String
    let defaultPlacement: TabPlacement

    var id: URL { url }

    static let popular: [BrowserSetupSiteSuggestion] = [
        make(
            title: "YouTube",
            address: "https://youtube.com",
            systemImage: "play.rectangle.fill",
            placement: .pinned
        ),
        make(
            title: "Instagram",
            address: "https://instagram.com",
            systemImage: "camera.fill",
            placement: .pinned
        ),
        make(
            title: "Reddit",
            address: "https://reddit.com",
            systemImage: "bubble.left.and.bubble.right.fill",
            placement: .pinned
        ),
        make(
            title: "Facebook",
            address: "https://facebook.com",
            systemImage: "person.2.fill",
            placement: .pinned
        ),
        make(
            title: "X",
            address: "https://x.com",
            systemImage: "text.bubble.fill",
            placement: .pinned
        ),
        make(
            title: "ChatGPT",
            address: "https://chatgpt.com",
            systemImage: "sparkles",
            placement: .saved
        ),
        make(
            title: "Wikipedia",
            address: "https://wikipedia.org",
            systemImage: "books.vertical.fill",
            placement: .saved
        ),
    ]

    private static func make(
        title: String,
        address: String,
        systemImage: String,
        placement: TabPlacement
    ) -> BrowserSetupSiteSuggestion {
        guard let url = URL(string: address) else {
            preconditionFailure("Invalid built-in site suggestion: \(address)")
        }
        return BrowserSetupSiteSuggestion(
            title: title,
            url: url,
            systemImage: systemImage,
            defaultPlacement: placement
        )
    }
}
