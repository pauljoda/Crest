import CoreGraphics

enum MobileSidebarRowLayoutPolicy {
    static let rootContentLeadingInset: CGFloat = 12
    static let folderNestingIndent: CGFloat = 14

    static func folderLeadingInset(depth: Int) -> CGFloat {
        rootContentLeadingInset + CGFloat(max(0, depth)) * folderNestingIndent
    }
}
