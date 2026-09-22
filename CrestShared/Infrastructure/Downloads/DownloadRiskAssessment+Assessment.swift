import Foundation
import UniformTypeIdentifiers

extension BrowserDownloadRiskVerdict {
    /// Supplies the platform's file-system-safe name and type-registry facts;
    /// the core decides the risk reasons and whether confirmation is needed.
    static func assess(
        suggestedFilename: String,
        mimeType: String?,
        isUserInitiated: Bool
    ) -> BrowserDownloadRiskVerdict {
        let sanitizedFilename = BrowserDownloadDestination.safeFilename(from: suggestedFilename)
        let extensionType = contentType(forFilename: sanitizedFilename)
        let declaredMIMEType = mimeType?.lowercased()
        let mimeContentType = declaredMIMEType.flatMap {
            UTType(tag: $0, tagClass: .mimeType, conformingTo: nil)
        }
        let typesRelated: Bool? = extensionType.flatMap { extensionType in
            mimeContentType.map {
                extensionType.conforms(to: $0) || $0.conforms(to: extensionType)
            }
        }
        return BrowserCorePolicy.downloadRisk(
            suggestedFilename: suggestedFilename,
            sanitizedFilename: sanitizedFilename,
            mimeType: declaredMIMEType,
            extensionRunsCode: runsCode(extensionType),
            mimeTypeRunsCode: runsCode(mimeContentType),
            typesRelated: typesRelated,
            isUserInitiated: isUserInitiated
        )
    }

    private static func contentType(forFilename filename: String) -> UTType? {
        let pathExtension = (filename as NSString).pathExtension
        guard !pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: pathExtension)
    }

    private static func runsCode(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return type.conforms(to: .executable)
            || type.conforms(to: .application)
            || type.conforms(to: .script)
            || type.conforms(to: .diskImage)
    }
}
