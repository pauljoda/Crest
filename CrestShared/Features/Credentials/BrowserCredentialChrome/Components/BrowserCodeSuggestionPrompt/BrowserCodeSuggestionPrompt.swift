import SwiftUI

// MARK: - Types

/// A login of the site that makes one-time codes, as the code popup lists it.
struct BrowserCodeSuggestion: Identifiable, Equatable {
    let descriptor: CredentialDescriptor
    let link: String

    var id: UUID { descriptor.id }
}

/// The popup under a field that takes a one-time code: each login of the site
/// that makes codes, with its live code and countdown, the login the page
/// just filled first. Choosing one fills the code, across split fields too.
/// It shows only when the Space has a code for the site.
struct BrowserCodeSuggestionPrompt: View {
    let request: BrowserCredentialFillRequest
    let port: BrowserCredentialFillPort
    let browser: BrowserStore
    let metrics: BrowserCredentialPromptMetrics

    @State private var suggestions: [BrowserCodeSuggestion]?
    @State private var selectedID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        // A zero-size anchor keeps the view on screen while it loads, so its
        // task runs: SwiftUI runs no task on a view with nothing in it.
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if let suggestions, !suggestions.isEmpty {
                BrowserCredentialPromptSurface(
                    accessibilityLabel: Text("Crest one-time codes"),
                    accessibilityIdentifier: "crest-code-suggestions",
                    width: metrics.fillPromptWidth,
                    metrics: metrics
                ) {
                    VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.contentSpacing) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 0) {
                                ForEach(suggestions) { suggestion in
                                    row(suggestion, now: context.date)
                                }
                            }
                        }
                        if let errorMessage {
                            BrowserCredentialPromptError(verbatim: errorMessage)
                        }
                        if let openPasswords = port.openPasswords {
                            BrowserCredentialPopupFooter(title: "Passwords…", metrics: metrics, open: openPasswords)
                        }
                    }
                }
            }
        }
        .task(id: request.id) { await load() }
        .onChange(of: port.keyPress) { _, press in
            press.map { answer($0.key) }
        }
        .onDisappear { port.holdKeys(false, request.id) }
    }

    private func row(_ suggestion: BrowserCodeSuggestion, now: Date) -> some View {
        let code = browser.oneTimeCode(forLink: suggestion.link, at: now)
        let isSelected = suggestion.id == selectedID
        return Button {
            fill(suggestion)
        } label: {
            HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                BrowserCredentialPromptIdentity(
                    kind: .suggestions, iconData: port.siteIconData, showsSiteIcon: port.siteIconData != nil,
                    tint: CrestBrandTheme.accent)
                VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.suggestionRowTextSpacing) {
                    Text(verbatim: code?.spaced ?? "––– –––")
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text(
                        verbatim: [suggestion.descriptor.username, spaceName].compactMap(\.self).joined(
                            separator: " · ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: BrowserCredentialPromptMetrics.suggestionRowSpacerLength)
                if let code { BrowserOneTimeCodeRing(code: code, now: now) }
            }
            .padding(.horizontal, metrics.suggestionRowHighlightBleed)
            .padding(.vertical, metrics.suggestionRowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.suggestionRowMinimumHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(
            BrowserCredentialPopupRowStyle(
                isSelected: isSelected, highlightCornerRadius: metrics.suggestionRowHighlightCornerRadius)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var spaceName: String? {
        browser.spaceModel(port.spaceID)?.settings.name
    }

    /// The site's logins that make codes, the one the page just filled first.
    private func load() async {
        suggestions = nil
        let logins = (try? await browser.credentialSuggestions(for: request.origin, in: port.spaceID)) ?? []
        var found: [BrowserCodeSuggestion] = []
        for login in logins {
            if let link = try? await browser.credentialExtras(id: login.id, in: port.spaceID)?.codeLink {
                found.append(BrowserCodeSuggestion(descriptor: login, link: link))
            }
        }
        guard !Task.isCancelled else { return }
        if let last = port.lastFilledCredentialID, let index = found.firstIndex(where: { $0.id == last }) {
            found.insert(found.remove(at: index), at: 0)
        }
        suggestions = found
        selectedID = found.first?.id
        if found.isEmpty {
            port.dismiss()
        } else {
            port.holdKeys(true, request.id)
        }
    }

    private func answer(_ key: BrowserCredentialPopupKey) {
        guard let suggestions, !suggestions.isEmpty else { return }
        if key.dismissesPopup {
            port.dismiss()
        } else if key.choosesSelection {
            if let selected = suggestions.first(where: { $0.id == selectedID }) {
                fill(selected)
            } else {
                port.dismiss()
            }
        } else {
            let index = suggestions.firstIndex { $0.id == selectedID } ?? 0
            selectedID = suggestions[min(max(index + key.step, 0), suggestions.count - 1)].id
        }
    }

    private func fill(_ suggestion: BrowserCodeSuggestion) {
        guard let fields = request.codeFields,
            let code = browser.oneTimeCode(forLink: suggestion.link, at: .now),
            let values = browser.spread(code.code, into: fields)
        else {
            errorMessage = String(localized: "This code doesn’t fit the page’s fields.")
            return
        }
        Task { @MainActor in
            do {
                try await port.fillValues(values, request.id)
            } catch {
                errorMessage = String(localized: "The form changed before Crest could fill it.")
            }
        }
    }
}
