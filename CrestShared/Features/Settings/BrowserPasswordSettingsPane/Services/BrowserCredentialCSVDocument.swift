import SwiftUI
import UniformTypeIdentifiers

struct BrowserCredentialCSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BrowserPortableArchiveError.missingFileContents
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Credential CSV import

struct BrowserCredentialCSVImportLimits: Equatable, Sendable {
    static let standard = BrowserCredentialCSVImportLimits(
        maximumByteCount: 16 * 1_024 * 1_024,
        maximumRowCount: 10_000,
        maximumColumnCount: 64,
        maximumFieldCharacterCount: 65_536
    )

    let maximumByteCount: Int
    let maximumRowCount: Int
    let maximumColumnCount: Int
    let maximumFieldCharacterCount: Int
}

enum BrowserCredentialCSVImportField: String, Equatable, Sendable {
    case origin = "site"
    case username
    case password
}

enum BrowserCredentialCSVImportError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case invalidEncoding
    case emptyFile
    case noCredentialRows
    case malformedCSV
    case tooManyRows
    case tooManyColumns
    case fieldTooLarge
    case missingHeader(field: BrowserCredentialCSVImportField)
    case ambiguousHeaders(field: BrowserCredentialCSVImportField)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "This password file is larger than Crest’s 16 MB import limit."
        case .invalidEncoding:
            "This password file is not valid UTF-8 text."
        case .emptyFile:
            "This password file is empty."
        case .noCredentialRows:
            "This password file contains supported headers but no credential rows."
        case .malformedCSV:
            "This password file contains malformed CSV quoting or columns."
        case .tooManyRows:
            "This password file contains more than 10,000 credential rows."
        case .tooManyColumns:
            "This password file contains too many columns."
        case .fieldTooLarge:
            "A field in this password file is too large to import safely."
        case .missingHeader(let field):
            "This password file has no supported \(field.rawValue) column."
        case .ambiguousHeaders(let field):
            "This password file has more than one possible \(field.rawValue) column. Remove the ambiguity and try again."
        }
    }
}

enum BrowserCredentialCSVImportFormat: String, Equatable, Sendable {
    case browser = "Browser CSV"
    case firefox = "Firefox CSV"
    case safari = "Safari CSV"
    case bitwarden = "Bitwarden CSV"
}

enum BrowserCredentialCSVRowRejectionReason: Equatable, Sendable {
    case invalidOrigin
    case emptyPassword
    case malformedRow

    var message: String {
        switch self {
        case .invalidOrigin: "The site is not a valid web address."
        case .emptyPassword: "The password is empty."
        case .malformedRow: "The row does not match the detected columns."
        }
    }
}

struct BrowserCredentialCSVRowRejection: Equatable, Sendable {
    let rowNumber: Int
    let reason: BrowserCredentialCSVRowRejectionReason
}

enum BrowserCredentialCSVRowWarningReason: Equatable, Sendable {
    case insecureOrigin

    var message: String {
        switch self {
        case .insecureOrigin:
            "This HTTP site is not encrypted. Crest will import the password for manual access but will not autofill it on an insecure connection."
        }
    }
}

struct BrowserCredentialCSVRowWarning: Equatable, Sendable {
    let rowNumber: Int
    let reason: BrowserCredentialCSVRowWarningReason
}

struct BrowserCredentialCSVImportRecord:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let rowNumber: Int
    let displayName: String?
    let origin: CredentialOrigin
    let username: String
    let password: String

    var description: String {
        "BrowserCredentialCSVImportRecord(row: \(rowNumber), origin: \(origin), username: <redacted>, password: <redacted>)"
    }

    var debugDescription: String { description }
}

struct BrowserCredentialCSVImport: Equatable, Sendable {
    let format: BrowserCredentialCSVImportFormat
    let records: [BrowserCredentialCSVImportRecord]
    let rejections: [BrowserCredentialCSVRowRejection]
}

enum BrowserCredentialCSVImportParser {
    static func parse(
        contentsOf url: URL,
        limits: BrowserCredentialCSVImportLimits = .standard
    ) throws -> BrowserCredentialCSVImport {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let cappedReadCount = limits.maximumByteCount == Int.max
            ? Int.max
            : limits.maximumByteCount + 1
        let data = try handle.read(upToCount: cappedReadCount) ?? Data()
        return try parse(data, limits: limits)
    }

    static func parse(
        _ data: Data,
        limits: BrowserCredentialCSVImportLimits = .standard
    ) throws -> BrowserCredentialCSVImport {
        guard data.count <= limits.maximumByteCount else {
            throw BrowserCredentialCSVImportError.fileTooLarge
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw BrowserCredentialCSVImportError.invalidEncoding
        }
        let rows = try BrowserRFC4180Parser.parse(text, limits: limits)
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        guard let headers = rows.first else {
            throw BrowserCredentialCSVImportError.emptyFile
        }
        let headerMap = try BrowserCredentialCSVHeaderMap(headers: headers)
        guard rows.count - 1 <= limits.maximumRowCount else {
            throw BrowserCredentialCSVImportError.tooManyRows
        }
        guard rows.count > 1 else {
            throw BrowserCredentialCSVImportError.noCredentialRows
        }

        var records: [BrowserCredentialCSVImportRecord] = []
        var rejections: [BrowserCredentialCSVRowRejection] = []
        records.reserveCapacity(rows.count - 1)
        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            guard row.count <= headers.count else {
                rejections.append(
                    BrowserCredentialCSVRowRejection(
                        rowNumber: rowNumber,
                        reason: .malformedRow
                    )
                )
                continue
            }
            let rawOrigin = headerMap.value(in: row, at: headerMap.originIndex)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let originString = rawOrigin.contains("://")
                ? rawOrigin
                : "https://\(rawOrigin)"
            guard let url = URL(string: originString),
                  let origin = CredentialOrigin(url: url) else {
                rejections.append(
                    BrowserCredentialCSVRowRejection(
                        rowNumber: rowNumber,
                        reason: .invalidOrigin
                    )
                )
                continue
            }
            let password = headerMap.value(in: row, at: headerMap.passwordIndex)
            guard !password.isEmpty else {
                rejections.append(
                    BrowserCredentialCSVRowRejection(
                        rowNumber: rowNumber,
                        reason: .emptyPassword
                    )
                )
                continue
            }
            let name = headerMap.nameIndex.map { headerMap.value(in: row, at: $0) }
            records.append(
                BrowserCredentialCSVImportRecord(
                    rowNumber: rowNumber,
                    displayName: BrowserStoredStringPolicy.normalized(name),
                    origin: origin,
                    username: headerMap.value(in: row, at: headerMap.usernameIndex),
                    password: password
                )
            )
        }
        return BrowserCredentialCSVImport(
            format: headerMap.format,
            records: records,
            rejections: rejections
        )
    }
}

private struct BrowserCredentialCSVHeaderMap {
    let format: BrowserCredentialCSVImportFormat
    let originIndex: Int
    let usernameIndex: Int
    let passwordIndex: Int
    let nameIndex: Int?

    init(headers: [String]) throws {
        let normalized = headers.map(Self.normalize)
        originIndex = try Self.requiredIndex(
            aliases: ["url", "origin", "website", "login_uri"],
            field: .origin,
            headers: normalized
        )
        usernameIndex = try Self.requiredIndex(
            aliases: ["username", "user", "login", "email", "login_username"],
            field: .username,
            headers: normalized
        )
        passwordIndex = try Self.requiredIndex(
            aliases: ["password", "pass", "login_password"],
            field: .password,
            headers: normalized
        )
        nameIndex = Self.optionalIndex(aliases: ["name", "title"], headers: normalized)

        let headerSet = Set(normalized)
        if headerSet.contains("login_uri") {
            format = .bitwarden
        } else if !headerSet.isDisjoint(with: ["httprealm", "formactionorigin", "guid"]) {
            format = .firefox
        } else if !headerSet.isDisjoint(with: ["otpauth", "otp_auth"]) {
            format = .safari
        } else {
            format = .browser
        }
    }

    func value(in row: [String], at index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    private static func requiredIndex(
        aliases: Set<String>,
        field: BrowserCredentialCSVImportField,
        headers: [String]
    ) throws -> Int {
        let matches = headers.indices.filter { aliases.contains(headers[$0]) }
        guard !matches.isEmpty else {
            throw BrowserCredentialCSVImportError.missingHeader(field: field)
        }
        guard matches.count == 1 else {
            throw BrowserCredentialCSVImportError.ambiguousHeaders(field: field)
        }
        return matches[0]
    }

    private static func optionalIndex(
        aliases: Set<String>,
        headers: [String]
    ) -> Int? {
        headers.indices.first { aliases.contains(headers[$0]) }
    }

    private static func normalize(_ header: String) -> String {
        header
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))
            )
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

private enum BrowserRFC4180Parser {
    static func parse(
        _ text: String,
        limits: BrowserCredentialCSVImportLimits
    ) throws -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var index = 0
        var inQuotes = false
        var afterClosingQuote = false
        var fieldStarted = false

        func validateField(_ value: String) throws {
            guard value.count <= limits.maximumFieldCharacterCount else {
                throw BrowserCredentialCSVImportError.fieldTooLarge
            }
        }

        func appendField() throws {
            try validateField(field)
            row.append(field)
            field = ""
            fieldStarted = false
            afterClosingQuote = false
            guard row.count <= limits.maximumColumnCount else {
                throw BrowserCredentialCSVImportError.tooManyColumns
            }
        }

        func appendRow() throws {
            try appendField()
            rows.append(row)
            row = []
            guard rows.count <= limits.maximumRowCount + 1 else {
                throw BrowserCredentialCSVImportError.tooManyRows
            }
        }

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if inQuotes {
                if character == "\"" {
                    if next == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    afterClosingQuote = true
                } else if character == "\r" || character == "\r\n" {
                    field.append("\n")
                    if next == "\n" { index += 1 }
                } else {
                    field.append(character)
                }
                try validateField(field)
                index += 1
                continue
            }

            if afterClosingQuote {
                if character == "," {
                    try appendField()
                } else if character == "\n" || character == "\r" || character == "\r\n" {
                    try appendRow()
                    if character == "\r", next == "\n" { index += 1 }
                } else {
                    throw BrowserCredentialCSVImportError.malformedCSV
                }
                index += 1
                continue
            }

            if character == "\"" {
                guard !fieldStarted, field.isEmpty else {
                    throw BrowserCredentialCSVImportError.malformedCSV
                }
                inQuotes = true
                fieldStarted = true
            } else if character == "," {
                try appendField()
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                try appendRow()
                if character == "\r", next == "\n" { index += 1 }
            } else {
                field.append(character)
                fieldStarted = true
                try validateField(field)
            }
            index += 1
        }

        guard !inQuotes else {
            throw BrowserCredentialCSVImportError.malformedCSV
        }
        if fieldStarted || afterClosingQuote || !field.isEmpty || !row.isEmpty {
            try appendRow()
        }
        return rows
    }
}

// MARK: - Import review and deterministic conflict resolution

struct BrowserCredentialImportGroupID:
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let origin: CredentialOrigin
    let normalizedUsername: String

    var description: String {
        "BrowserCredentialImportGroupID(origin: \(origin), username: <redacted>)"
    }

    var debugDescription: String { description }
}

enum BrowserCredentialImportSelection: Equatable, Hashable, Sendable {
    case existing
    case imported(rowNumber: Int)
    case skip
}

struct BrowserCredentialImportGroup:
    Identifiable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let id: BrowserCredentialImportGroupID
    let origin: CredentialOrigin
    let username: String
    let candidates: [BrowserCredentialCSVImportRecord]
    let collapsedDuplicateRowCount: Int
    let requiresChoice: Bool
    fileprivate let existingCredential: BrowserCredential?
    var selection: BrowserCredentialImportSelection

    var hasExistingCredential: Bool { existingCredential != nil }
    var existingPasswordForReview: String? { existingCredential?.password }

    var description: String {
        "BrowserCredentialImportGroup(origin: \(origin), username: <redacted>, candidates: \(candidates.map(\.rowNumber)), existing: \(hasExistingCredential))"
    }

    var debugDescription: String { description }
}

struct BrowserCredentialImportSummary: Equatable, Sendable, Identifiable {
    let id = UUID()
    let acceptedCount: Int
    let skippedCount: Int
    let warningCount: Int
    let rejectedCount: Int

    init(
        acceptedCount: Int,
        skippedCount: Int,
        warningCount: Int = 0,
        rejectedCount: Int
    ) {
        self.acceptedCount = acceptedCount
        self.skippedCount = skippedCount
        self.warningCount = warningCount
        self.rejectedCount = rejectedCount
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.acceptedCount == rhs.acceptedCount
            && lhs.skippedCount == rhs.skippedCount
            && lhs.warningCount == rhs.warningCount
            && lhs.rejectedCount == rhs.rejectedCount
    }
}

struct BrowserCredentialImportResolution: Sendable {
    let credentials: [BrowserCredential]
    let summary: BrowserCredentialImportSummary
}

struct BrowserCredentialImportPlan:
    Identifiable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let id = UUID()
    let format: BrowserCredentialCSVImportFormat
    let destination: BrowserSpaceRuntimeAssignment
    let rejections: [BrowserCredentialCSVRowRejection]
    let warnings: [BrowserCredentialCSVRowWarning]
    private(set) var groups: [BrowserCredentialImportGroup]
    private let existingCredentials: [BrowserCredential]
    private let synchronizesWithICloud: Bool
    private let now: Date

    init(
        format: BrowserCredentialCSVImportFormat,
        records: [BrowserCredentialCSVImportRecord],
        rejections: [BrowserCredentialCSVRowRejection],
        existingCredentials: [BrowserCredential],
        destination: BrowserSpaceRuntimeAssignment,
        synchronizesWithICloud: Bool,
        now: Date = .now
    ) {
        self.format = format
        self.destination = destination
        self.rejections = rejections
        warnings = records.compactMap { record in
            guard !record.origin.isSecure else { return nil }
            return BrowserCredentialCSVRowWarning(
                rowNumber: record.rowNumber,
                reason: .insecureOrigin
            )
        }
        self.existingCredentials = existingCredentials
        self.synchronizesWithICloud = synchronizesWithICloud
        self.now = now

        let existingByID = Dictionary(
            grouping: existingCredentials.filter { $0.descriptor.scope == .webForm },
            by: { Self.groupID(origin: $0.descriptor.origin, username: $0.descriptor.username) }
        )
        let recordsByID = Dictionary(
            grouping: records,
            by: { Self.groupID(origin: $0.origin, username: $0.username) }
        )
        groups = recordsByID.map { id, groupedRecords in
            let sortedRecords = groupedRecords.sorted { $0.rowNumber < $1.rowNumber }
            var candidates: [BrowserCredentialCSVImportRecord] = []
            for record in sortedRecords where !candidates.contains(where: { $0.password == record.password }) {
                candidates.append(record)
            }
            let existing = existingByID[id]?.max(by: Self.isLessRecent)
            let onlyCandidateMatchesExisting = candidates.count == 1
                && candidates.first?.password == existing?.password
            let requiresChoice = candidates.count > 1
                || (existing != nil && !onlyCandidateMatchesExisting)
            let selection: BrowserCredentialImportSelection
            if let existing {
                selection = .existing
                _ = existing
            } else if let first = candidates.first {
                selection = .imported(rowNumber: first.rowNumber)
            } else {
                selection = .skip
            }
            return BrowserCredentialImportGroup(
                id: id,
                origin: sortedRecords[0].origin,
                username: sortedRecords[0].username,
                candidates: candidates,
                collapsedDuplicateRowCount: sortedRecords.count - candidates.count,
                requiresChoice: requiresChoice,
                existingCredential: existing,
                selection: selection
            )
        }
        .sorted {
            if $0.origin.description != $1.origin.description {
                return $0.origin.description < $1.origin.description
            }
            return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
        }
    }

    var description: String {
        "BrowserCredentialImportPlan(format: \(format.rawValue), destination: \(destination.spaceID), groups: \(groups.count), warnings: \(warnings.count), rejected: \(rejections.count), secrets: <redacted>)"
    }

    var debugDescription: String { description }

    var proposedImportCount: Int {
        groups.reduce(into: 0) { count, group in
            if case .imported = group.selection { count += 1 }
        }
    }

    var conflictCount: Int {
        groups.count(where: \.requiresChoice)
    }

    func groups(matching query: String) -> [BrowserCredentialImportGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            group.origin.description.localizedCaseInsensitiveContains(query)
                || group.username.localizedCaseInsensitiveContains(query)
                || group.candidates.contains {
                    $0.displayName?.localizedCaseInsensitiveContains(query) == true
                }
        }
    }

    mutating func select(
        _ selection: BrowserCredentialImportSelection,
        for id: BrowserCredentialImportGroupID
    ) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        switch selection {
        case .existing where !groups[index].hasExistingCredential:
            return
        case .imported(let rowNumber)
            where !groups[index].candidates.contains(where: { $0.rowNumber == rowNumber }):
            return
        default:
            groups[index].selection = selection
        }
    }

    func matchesExistingInventory(_ credentials: [BrowserCredential]) -> Bool {
        let order: (BrowserCredential, BrowserCredential) -> Bool = {
            $0.descriptor.id.rawValue.uuidString < $1.descriptor.id.rawValue.uuidString
        }
        return existingCredentials.sorted(by: order) == credentials.sorted(by: order)
    }

    func resolvedInventory() throws -> BrowserCredentialImportResolution {
        var resolved = existingCredentials
        var acceptedCount = 0
        for group in groups {
            guard case .imported(let rowNumber) = group.selection,
                  let candidate = group.candidates.first(where: { $0.rowNumber == rowNumber })
            else { continue }

            if let existing = group.existingCredential {
                guard candidate.password != existing.password else { continue }
                guard let index = resolved.firstIndex(where: {
                    $0.descriptor.id == existing.descriptor.id
                }) else {
                    throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
                }
                var descriptor = existing.descriptor
                descriptor.username = candidate.username
                descriptor.displayName = candidate.displayName ?? descriptor.displayName
                descriptor.updatedAt = now
                resolved[index] = BrowserCredential(
                    descriptor: descriptor,
                    password: candidate.password
                )
            } else {
                resolved.append(
                    BrowserCredential(
                        descriptor: CredentialDescriptor(
                            spaceID: destination.spaceID,
                            origin: candidate.origin,
                            username: candidate.username,
                            displayName: candidate.displayName,
                            createdAt: now,
                            isSynchronizable: synchronizesWithICloud
                        ),
                        password: candidate.password
                    )
                )
            }
            acceptedCount += 1
        }
        let validRowCount = groups.reduce(0) {
            $0 + $1.candidates.count + $1.collapsedDuplicateRowCount
        }
        return BrowserCredentialImportResolution(
            credentials: resolved,
            summary: BrowserCredentialImportSummary(
                acceptedCount: acceptedCount,
                skippedCount: validRowCount - acceptedCount,
                warningCount: warnings.count,
                rejectedCount: rejections.count
            )
        )
    }

    private static func groupID(
        origin: CredentialOrigin,
        username: String
    ) -> BrowserCredentialImportGroupID {
        BrowserCredentialImportGroupID(
            origin: origin,
            normalizedUsername: username.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
    }

    private static func isLessRecent(
        _ lhs: BrowserCredential,
        _ rhs: BrowserCredential
    ) -> Bool {
        BrowserCredentialRecencyPolicy.isLessRecent(
            lhs.descriptor,
            rhs.descriptor
        )
    }
}
