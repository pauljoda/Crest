import SwiftUI
import UniformTypeIdentifiers

/// Set Up Code: finds a login's setup key in a QR code on the page, a pasted
/// key or `otpauth` link, a chosen image, or on iPhone the camera, shows the
/// code it makes, and adds it to the login.
struct BrowserCodeSetupSheet: View {
    let browser: BrowserStore
    let origin: CredentialOrigin
    /// Takes a snapshot of the page the code is being set up on, where the
    /// shell can.
    let scanPage: (() async -> CGImage?)?
    /// Scans with the camera, on a device that has one.
    let scanWithCamera: (() async -> String?)?
    let add: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var found: BrowserCodeSetupPreview?
    @State private var problem: String?
    @State private var isChoosingImage = false
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let scanPage {
                        option(
                            "Scan This Page", detail: "Finds the QR code on \(origin.host)",
                            systemImage: "qrcode.viewfinder"
                        ) {
                            Task { await scan(scanPage) }
                        }
                        .disabled(isScanning)
                    }
                    if let scanWithCamera {
                        option("Scan with Camera", detail: "Point the camera at the QR code", systemImage: "camera") {
                            Task {
                                if let payload = await scanWithCamera() { read(payload) }
                            }
                        }
                    }
                    option("Choose Image…", detail: "A saved picture of the QR code", systemImage: "photo") {
                        isChoosingImage = true
                    }
                }
                Section("Paste setup key or link") {
                    TextField("Setup key or link", text: $pasted, prompt: Text("JBSW Y3DP or otpauth://…"))
                        .autocorrectionDisabled()
                        .onSubmit { read(pasted) }
                        .accessibilityIdentifier("code-setup-paste")
                    Button("Read Key") { read(pasted) }
                        .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let found {
                    Section("Code") {
                        BrowserCodeSetupPreviewRow(browser: browser, preview: found)
                    }
                }
                if let problem {
                    BrowserCredentialErrorSection(message: problem)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set Up Code")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Code") {
                        guard let found else { return }
                        add(found.link)
                        dismiss()
                    }
                    .disabled(found == nil)
                    .accessibilityIdentifier("code-setup-add")
                }
            }
        }
        .crestSheetSize(minWidth: 400, idealWidth: 460, minHeight: 380, idealHeight: 460)
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            Task { await readImage(at: url) }
        }
    }

    private func option(
        _ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CrestSpacing.medium) {
                CrestIconTile(systemImage: systemImage, color: CrestBrandTheme.accent, size: 28, symbolSize: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(CrestTypography.controlTitle)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func read(_ text: String) {
        switch browser.codeSetup(from: text) {
        case .success(let preview):
            found = preview
            problem = nil
        case .failure(let failure):
            found = nil
            problem = failure.message
        }
    }

    private func scan(_ snapshot: () async -> CGImage?) async {
        isScanning = true
        defer { isScanning = false }
        guard let image = await snapshot() else {
            problem = String(localized: "Crest couldn’t see the page.")
            return
        }
        await readCodes(in: image)
    }

    private func readImage(at url: URL) async {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            problem = String(localized: "Crest couldn’t open that image.")
            return
        }
        await readCodes(in: image)
    }

    private func readCodes(in image: CGImage) async {
        let payloads = await BrowserCodeImageReader.payloads(in: image)
        guard !payloads.isEmpty else {
            found = nil
            problem = String(localized: "There’s no QR code there.")
            return
        }
        // The first QR code that sets up a code wins; another, such as a link
        // to an app store, is passed over.
        for payload in payloads {
            if case .success(let preview) = browser.codeSetup(from: payload) {
                found = preview
                problem = nil
                return
            }
        }
        read(payloads[0])
    }
}

/// A setup key's account and the code it makes now, counting down.
struct BrowserCodeSetupPreviewRow: View {
    let browser: BrowserStore
    let preview: BrowserCodeSetupPreview

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: preview.title).font(CrestTypography.controlTitle)
                    if let code = browser.oneTimeCode(forLink: preview.link, at: context.date) {
                        Text(verbatim: code.spaced).font(.title3.monospacedDigit())
                    }
                }
                Spacer()
                if let code = browser.oneTimeCode(forLink: preview.link, at: context.date) {
                    BrowserOneTimeCodeRing(code: code, now: context.date)
                }
            }
        }
    }
}
