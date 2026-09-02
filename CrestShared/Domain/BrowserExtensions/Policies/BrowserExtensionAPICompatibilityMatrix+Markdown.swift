import Foundation

/// Markdown projection of the executable compatibility matrix.
///
/// The tables published in `Documentation/ExtensionAPICompatibilityMatrix.md`
/// and in the public help center are generated from these functions so a
/// routing change cannot drift away from its documentation. Prose that cannot
/// be derived from the matrix — boundary notes, acceptance criteria — stays
/// hand written outside the generated block.
extension BrowserExtensionAPICompatibilityMatrix {
    /// Opens the generated region in every documentation file.
    static let generatedDocumentationBeginMarker =
        "BEGIN GENERATED: BrowserExtensionAPICompatibilityMatrix"

    /// Closes the generated region in every documentation file.
    static let generatedDocumentationEndMarker = "END GENERATED"

    /// The complete generated documentation body, without file-specific
    /// comment markers.
    static func generatedDocumentationMarkdown() -> String {
        [
            pinnedRevisionsMarkdown(),
            namespaceTableMarkdown(),
            memberTableMarkdown(),
        ].joined(separator: "\n\n")
    }

    /// The pinned reference revisions this matrix was reviewed against.
    static func pinnedRevisionsMarkdown() -> String {
        let rows = [
            ["Chromium schemas", "`\(chromiumRevision)`"],
            ["Firefox schemas", "`\(firefoxRevision)`"],
            ["WebKit extension IDL", "`\(webKitRevision)`"],
            ["Apple SDK", appleSDKBuild],
        ]
        return """
            ### Pinned revisions

            \(markdownTable(headers: ["Source", "Pinned revision"], rows: rows))
            """
    }

    /// One row per namespace contract, ordered by namespace name.
    static func namespaceTableMarkdown() -> String {
        let rows = contracts.sorted { $0.namespace < $1.namespace }.map { contract in
            [
                "`\(contract.namespace)`",
                documentationLabel(contract.chromium),
                documentationLabel(contract.firefox),
                documentationLabel(contract.webKit),
                documentationLabel(contract.crest),
                documentationProcesses(contract.processes),
                documentationNameList(contract.permissionNames),
                documentationExposureGate(contract.namespace),
                documentationNameList(contract.capabilityBrokerPermissions),
            ]
        }
        let headers = [
            "Namespace",
            "Chrome",
            "Firefox",
            "WebKit",
            "Crest route",
            "Processes",
            "Permissions",
            "Exposure",
            "Broker",
        ]
        return """
            ### Namespace routes

            Routes are **Native** (WebKit unchanged), **Native + patch** (WebKit identity kept, one contract gap \
            filled), **Emulated** (Crest owns the implementation), and **Unavailable** (no false success). \
            Processes are **BG** (background worker or page), **EP** (extension page or popup), **CS** (content \
            script), and **DT** (DevTools page). Permissions lists the manifest permissions the matrix associates \
            with the namespace; Exposure is the narrower question the compatibility runtime actually asks before \
            it publishes `browser.<namespace>` at all, and the two differ where Chrome defines a namespace \
            regardless of the manifest. Broker lists the permissions the Crest capability broker will \
            authorize for that namespace.

            \(markdownTable(headers: headers, rows: rows))
            """
    }

    /// One row per member-level route, ordered by member path.
    static func memberTableMarkdown() -> String {
        let rows = members.sorted { $0.path < $1.path }.map { member in
            [
                "`\(member.path)`",
                documentationLabel(member.webKit),
                documentationLabel(member.crest),
                documentationProcesses(member.processes),
                member.hidesWebKitMember ? "Yes" : "—",
            ]
        }
        let headers = [
            "Member",
            "WebKit",
            "Crest route",
            "Processes",
            "Hidden from WebKit",
        ]
        return """
            ### Member routes

            A namespace can stay native while a single dynamic member is replaced. **Hidden from WebKit** marks \
            the members Crest removes from the native surface before the extension context loads.

            \(markdownTable(headers: headers, rows: rows))
            """
    }

    private static func markdownTable(headers: [String], rows: [[String]]) -> String {
        let separator = Array(repeating: "---", count: headers.count)
        return ([headers, separator] + rows)
            .map { "| " + $0.joined(separator: " | ") + " |" }
            .joined(separator: "\n")
    }

    private static func documentationProcesses(
        _ processes: Set<BrowserExtensionExecutionProcess>
    ) -> String {
        guard !processes.isEmpty else { return "—" }
        return
            processes
            .sorted { documentationOrder($0) < documentationOrder($1) }
            .map(documentationAbbreviation)
            .joined(separator: ", ")
    }

    /// What the runtime's own gate asks before publishing the namespace.
    ///
    /// The `Permissions` column is the matrix's association, which is what the
    /// broker and the WebKit hide list filter on. Exposure is `namespacePermissions`,
    /// the list the generated runtime embeds and tests, and it is empty for a
    /// namespace Chrome defines regardless of the manifest. Rendering the
    /// association in both places published a gate the runtime does not apply.
    private static func documentationExposureGate(
        _ namespace: String
    ) -> String {
        guard let permissions = namespacePermissions[namespace] else {
            return "Always"
        }
        guard !permissions.isEmpty else { return "Always" }
        return permissions.sorted().map { "`\($0)`" }
            .joined(separator: ", ")
    }

    private static func documentationNameList(_ names: Set<String>) -> String {
        guard !names.isEmpty else { return "—" }
        return names.sorted().map { "`\($0)`" }.joined(separator: ", ")
    }

    private static func documentationLabel(
        _ support: BrowserExtensionReferenceSupport
    ) -> String {
        switch support {
        case .native: "Native"
        case .partial: "Partial"
        case .unavailable: "Unavailable"
        }
    }

    private static func documentationLabel(
        _ route: BrowserExtensionCrestRoute
    ) -> String {
        switch route {
        case .native: "Native"
        case .nativePatched: "Native + patch"
        case .emulated: "Emulated"
        case .presenceOnly: "Presence only"
        case .unavailable: "Unavailable"
        }
    }

    private static func documentationAbbreviation(
        _ process: BrowserExtensionExecutionProcess
    ) -> String {
        switch process {
        case .background: "BG"
        case .extensionPage: "EP"
        case .contentScript: "CS"
        case .devtoolsPage: "DT"
        }
    }

    /// Reading order for the abbreviations: outermost extension process first.
    private static func documentationOrder(
        _ process: BrowserExtensionExecutionProcess
    ) -> Int {
        switch process {
        case .background: 0
        case .extensionPage: 1
        case .contentScript: 2
        case .devtoolsPage: 3
        }
    }
}
