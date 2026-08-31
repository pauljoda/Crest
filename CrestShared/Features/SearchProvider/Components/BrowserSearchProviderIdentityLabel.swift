import SwiftUI

enum BrowserSearchProviderIdentityLabelLayout: Equatable {
    case compact
    case touch

    static var platformDefault: Self {
        #if os(macOS)
            .compact
        #else
            .touch
        #endif
    }

    var iconSize: CGFloat {
        switch self {
        case .compact: 20
        case .touch: 28
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact: 4
        case .touch: 8
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: 0
        case .touch: 4
        }
    }
}

struct BrowserSearchProviderIdentityLabel: View {
    let provider: BrowserSearchProvider
    var profileID: UUID? = nil
    var title: String? = nil
    var layout: BrowserSearchProviderIdentityLabelLayout = .platformDefault

    var body: some View {
        HStack(spacing: layout.spacing) {
            BrowserSearchProviderIcon(
                provider: provider,
                profileID: profileID,
                size: layout.iconSize
            )
            Text(title ?? provider.title)
        }
        .padding(.vertical, layout.verticalPadding)
    }
}
