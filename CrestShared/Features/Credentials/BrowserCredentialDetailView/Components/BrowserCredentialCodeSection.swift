import SwiftUI

/// The login's one-time code: the code and its countdown once the person
/// authenticated, and in Edit, a way to set one up or remove it.
struct BrowserCredentialCodeSection: View {
    @Bindable var model: BrowserCredentialDetailModel
    let browser: BrowserStore?
    var scanPage: (() async -> CGImage?)? = nil
    var scanWithCamera: (() async -> String?)? = nil

    @State private var isSettingUp = false

    var body: some View {
        if let draft = $model.draft.editing {
            Section("Code") {
                if let link = draft.wrappedValue.codeLink {
                    if let browser {
                        BrowserCodeSetupPreviewRow(browser: browser, preview: browser.codePreview(forLink: link))
                    }
                    Button("Remove Code", systemImage: "minus.circle", role: .destructive) {
                        draft.wrappedValue.codeLink = nil
                    }
                } else if let browser {
                    Button("Set Up Code…", systemImage: "qrcode") { isSettingUp = true }
                        .accessibilityIdentifier("set-up-code")
                        // On the button, not the section, which would hand
                        // the sheet to every row it holds.
                        .sheet(isPresented: $isSettingUp) {
                            BrowserCodeSetupSheet(
                                browser: browser, origin: model.descriptor.origin, scanPage: scanPage,
                                scanWithCamera: scanWithCamera
                            ) { draft.wrappedValue.codeLink = $0 }
                        }
                }
            }
        } else if let link = model.revealedExtras?.codeLink, let browser {
            Section("Code") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let code = browser.oneTimeCode(forLink: link, at: context.date) {
                        HStack {
                            Text(verbatim: code.spaced)
                                .font(.title3.monospacedDigit())
                                .textSelection(.enabled)
                            Spacer()
                            BrowserOneTimeCodeRing(code: code, now: context.date)
                            Button {
                                let lease = BrowserCredentialSecretLease.clipboard(
                                    password: code.code, issuedAt: context.date)
                                if BrowserCredentialClipboard.write(lease) { BrowserNoticeCenter.shared.post(.copied) }
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(CrestChromeButtonStyle())
                            .help("Copy Code")
                            .accessibilityLabel("Copy Code")
                        }
                    }
                }
            }
        } else if model.hasCode {
            Section("Code") {
                Button("Show Code", systemImage: "clock.badge.checkmark") {
                    Task { await model.revealExtras() }
                }
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("reveal-credential-code")
            }
        }
    }
}
