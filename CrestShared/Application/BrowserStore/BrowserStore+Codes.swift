import Foundation

// MARK: - Types

/// A setup key read for a login: the canonical `otpauth` link it is kept as,
/// and whose account it names.
struct BrowserCodeSetupPreview: Equatable, Sendable, CustomStringConvertible {
    let link: String
    let issuer: String
    let account: String

    /// The issuer and account, as the person reads them.
    var title: String {
        [issuer, account].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty
            ?? String(localized: "One-time code")
    }

    var description: String { "BrowserCodeSetupPreview(issuer: \(issuer), link: <redacted>)" }
}

/// Why a setup key can't make codes, in words.
struct BrowserCodeSetupProblem: Error, Equatable {
    let message: String
}

// MARK: - One-time codes

extension BrowserStore {
    /// What `text` sets up, a pasted key, a link or a QR code's words, as
    /// the core reads it: the link Crest keeps for it, or why it can't.
    func codeSetup(from text: String) -> Result<BrowserCodeSetupPreview, BrowserCodeSetupProblem> {
        guard let parsed = try? core.query(ParseCodeSetup(text: text)) else {
            return .failure(BrowserCodeSetupProblem(message: String(localized: "This isn’t a setup key.")))
        }
        guard let setup = parsed.setup else {
            return .failure(
                BrowserCodeSetupProblem(
                    message: parsed.refusal.map { String(localized: $0.message) }
                        ?? String(localized: "This isn’t a setup key.")))
        }
        guard let link = try? core.query(WriteCodeSetup(setup: setup)).link else {
            return .failure(BrowserCodeSetupProblem(message: String(localized: "This isn’t a setup key.")))
        }
        return .success(BrowserCodeSetupPreview(link: link, issuer: setup.issuer, account: setup.account))
    }

    /// The setup a kept link names, for showing whose code it is.
    func codePreview(forLink link: String) -> BrowserCodeSetupPreview {
        (try? codeSetup(from: link).get()) ?? BrowserCodeSetupPreview(link: link, issuer: "", account: "")
    }

    /// The code the kept link `link` makes at `date`, or nil when the core
    /// can't make one.
    func oneTimeCode(forLink link: String, at date: Date) -> BrowserOneTimeCode? {
        guard let setup = try? core.query(ParseCodeSetup(text: link)).setup,
            let reading = try? core.query(OneTimeCode(setup: setup, now: date.timeIntervalSince1970))
        else { return nil }
        return BrowserOneTimeCode(
            code: reading.code, validFrom: Date(timeIntervalSince1970: reading.validFrom),
            validUntil: Date(timeIntervalSince1970: reading.validUntil))
    }

    /// The values that put `code` into `fields`: the whole code in one field,
    /// or a character in each of the split fields.
    func spread(_ code: String, into fields: OneTimeCodeFields) -> [BrowserAutofillValue]? {
        (try? core.query(SpreadOneTimeCode(fields: fields, code: code)))?.entries.map {
            BrowserAutofillValue(field: $0.field, value: $0.text)
        }
    }
}
