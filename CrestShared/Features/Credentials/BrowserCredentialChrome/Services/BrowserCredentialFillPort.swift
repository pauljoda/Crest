import CoreGraphics
import Foundation

/// Everything the credential fill prompts need from the page layer, and nothing
/// else.
///
/// The two shells reach different pages — one a pooled windowed page, the other
/// the compact shell's resident page — but a fill prompt only ever asks the same
/// four things, and both pages already answer them with identical signatures.
/// They live here as closures rather than behind a protocol, for the same reason
/// `BrowserFindPort`'s do: there is no third implementation to swap in, only two
/// concrete pages, each bound where its shell presents the chrome.
///
/// `spaceID` is carried rather than read back through the app's selection, for
/// the reason `BrowserCredentialPageState` states: a prompt must keep asking the
/// Space its form was submitted in, even after the person has selected another.
///
/// None of the closures carries an isolation annotation, exactly like
/// `BrowserSidebarNavigationPort`'s: annotating them `@MainActor` would also
/// make them `@Sendable`, which the plain function values a View hands over are
/// not. The struct itself is isolated instead.
@MainActor
struct BrowserCredentialFillPort {
    /// The Space this page belongs to — the vault a prompt reads and the
    /// identity it names.
    let spaceID: UUID

    /// How one of the page's CSS pixels maps to a point in this shell — the
    /// page's zoom, and the only thing standing between a rect the page
    /// reported and the place a panel is drawn.
    let contentScale: CGFloat

    /// The page's own icon, where it has loaded one. A prompt shows it beside
    /// the origin it is about, so the site is recognised before it is read.
    let siteIconData: Data?

    /// Puts a saved credential into the form the request came from. Throws
    /// where the form moved on before the fill could land.
    let fill: (BrowserCredential, UUID) async throws -> Void

    /// Puts a freshly generated password into the form and its confirmation
    /// field.
    let fillGeneratedPassword: (String, UUID) async throws -> Void

    /// What the form's username field holds now, so a password Crest makes is
    /// saved under the account it is for.
    let formUsername: (UUID) async -> String?

    /// Closes the prompt without filling anything.
    let dismiss: () -> Void

    /// The latest key the page held back for the prompt on show.
    let keyPress: BrowserCredentialKeyPress?

    /// Sends the request's field's arrow, Return and Escape keys to the
    /// prompt while it shows, or gives them back to the page.
    let holdKeys: (Bool, UUID) -> Void

    /// Opens Settings at the Space's passwords, where the shell can.
    var openPasswords: (() -> Void)? = nil
}

extension BrowserCredentialFillPort {
    // MARK: - Initializers

    /// What a credential fill prompt asks of `page`, whose page content the
    /// shell draws at `contentScale`.
    init(page: BrowserPlatformPage, contentScale: CGFloat, openPasswords: (() -> Void)? = nil) {
        self.init(
            spaceID: page.spaceID,
            contentScale: contentScale,
            siteIconData: page.faviconData,
            fill: { credential, requestID in try await page.fillCredential(credential, for: requestID) },
            fillGeneratedPassword: { password, requestID in
                try await page.fillGeneratedPassword(password, for: requestID)
            },
            formUsername: { requestID in await page.credentialFormUsername(for: requestID) },
            dismiss: page.dismissCredentialFillRequest,
            keyPress: page.credentialKeyPress,
            holdKeys: { hold, requestID in
                Task { @MainActor in await page.holdCredentialKeys(hold, for: requestID) }
            },
            openPasswords: openPasswords)
    }
}
