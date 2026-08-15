import Foundation
import UniformTypeIdentifiers

extension BrowserDownloadRiskAssessment {
    static func assess(suggestedFilename: String, mimeType: String?) -> BrowserDownloadRiskAssessment {
        let sanitizedFilename = BrowserDownloadDestination.safeFilename(from: suggestedFilename)
        let extensionType = contentType(forFilename: sanitizedFilename)
        let declaredMIMEType = mimeType?.lowercased()
        let mimeContentType = declaredMIMEType.flatMap {
            UTType(tag: $0, tagClass: .mimeType, conformingTo: nil)
        }
        let extensionIsDangerous = isDangerous(extensionType, filename: sanitizedFilename)
        let mimeIsDangerous =
            isDangerous(mimeContentType, filename: nil)
            || declaredMIMEType.map(dangerousMIMETypes.contains) == true
        var reasons: [BrowserDownloadRiskReason] = []

        if extensionIsDangerous || mimeIsDangerous {
            reasons.append(.executableOrInstaller)
        }
        if BrowserDownloadDestination.containsDeceptiveUnicode(suggestedFilename) {
            reasons.append(.deceptiveFilename)
        }
        if extensionIsDangerous || mimeIsDangerous,
            let extensionType,
            let mimeContentType,
            !extensionType.conforms(to: mimeContentType),
            !mimeContentType.conforms(to: extensionType)
        {
            reasons.append(.dangerousTypeMismatch)
        }

        return BrowserDownloadRiskAssessment(
            sanitizedFilename: sanitizedFilename,
            reasons: reasons
        )
    }

    private static func contentType(forFilename filename: String) -> UTType? {
        let pathExtension = (filename as NSString).pathExtension
        guard !pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: pathExtension)
    }

    private static func isDangerous(_ type: UTType?, filename: String?) -> Bool {
        if let type,
            type.conforms(to: .executable)
                || type.conforms(to: .application)
                || type.conforms(to: .script)
                || type.conforms(to: .diskImage)
        {
            return true
        }

        guard let filename else { return false }
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        return dangerousExtensions.contains(pathExtension)
    }

    private static let dangerousExtensions: Set<String> = [
        "app", "application", "bat", "bin", "cmd", "com", "command", "csh", "dmg",
        "exe", "jar", "ksh", "mobileconfig", "mpkg", "msi", "pkg", "ps1", "reg",
        "run", "scpt", "scr", "sh", "tool", "vbs", "workflow", "zsh",
    ]

    private static let dangerousMIMETypes: Set<String> = [
        "application/x-apple-diskimage",
        "application/x-bat",
        "application/x-executable",
        "application/x-mach-binary",
        "application/x-msdownload",
        "application/x-msi",
        "application/x-powershell",
        "application/x-sh",
        "application/x-shellscript",
    ]
}
