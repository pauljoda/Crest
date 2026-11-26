import AppKit
import CoreText
import SwiftUI

struct BrowserWebKitFeatureFlagList: View {
    let groups: [BrowserWebKitFeatureFlagGroup]
    let searchText: String
    let store: BrowserWebKitFeatureFlagStore

    var body: some View {
        BrowserWebKitFeatureFlagTableView(
            groups: groups,
            overrides: store.overrides,
            setOverride: { override, flag in
                store.setOverride(override, for: flag)
            }
        )
        .overlay {
            if groups.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "No Matching Feature Flags",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .accessibilityIdentifier("webkit-feature-list")
    }
}

/// Pure AppKit recycled `NSTableView` with custom CoreGraphics text drawing
/// (zero per-cell `NSTextField` / Auto Layout / `NSPopUpButton` churn) so
/// scrolling hundreds of WebKit feature flags stays locked at 120 fps.
private struct BrowserWebKitFeatureFlagTableView: NSViewRepresentable {
    let groups: [BrowserWebKitFeatureFlagGroup]
    let overrides: [String: BrowserWebKitFeatureFlagOverride]
    let setOverride: @MainActor (BrowserWebKitFeatureFlagOverride?, BrowserWebKitFeatureFlag) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(setOverride: setOverride)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = .zero
        tableView.usesAutomaticRowHeights = false
        tableView.style = .plain
        tableView.rowSizeStyle = .custom
        tableView.gridStyleMask = []

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FeatureFlagColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        context.coordinator.tableView = tableView

        scrollView.documentView = tableView
        context.coordinator.update(groups: groups, overrides: overrides, setOverride: setOverride)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(groups: groups, overrides: overrides, setOverride: setOverride)
    }

    enum Row: Equatable {
        case header(BrowserWebKitFeatureCategory)
        case flag(BrowserWebKitFeatureFlag, isLastInSection: Bool)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let headerIdentifier = NSUserInterfaceItemIdentifier("FeatureFlagHeaderCell")
        private static let flagIdentifier = NSUserInterfaceItemIdentifier("FeatureFlagRowCell")
        private static let headerHeight: CGFloat = 34

        weak var tableView: NSTableView?
        private var rows: [Row] = []
        private var overrides: [String: BrowserWebKitFeatureFlagOverride] = [:]
        private var setOverride: @MainActor (BrowserWebKitFeatureFlagOverride?, BrowserWebKitFeatureFlag) -> Void
        private var cachedWidthBucket = 0
        private var cachedHeights: [String: CGFloat] = [:]

        init(setOverride: @escaping @MainActor (BrowserWebKitFeatureFlagOverride?, BrowserWebKitFeatureFlag) -> Void) {
            self.setOverride = setOverride
        }

        func update(
            groups: [BrowserWebKitFeatureFlagGroup],
            overrides: [String: BrowserWebKitFeatureFlagOverride],
            setOverride: @escaping @MainActor (BrowserWebKitFeatureFlagOverride?, BrowserWebKitFeatureFlag) -> Void
        ) {
            self.setOverride = setOverride
            var nextRows: [Row] = []
            nextRows.reserveCapacity(groups.reduce(0) { $0 + 1 + $1.flags.count })
            for group in groups {
                nextRows.append(.header(group.category))
                let lastID = group.flags.last?.id
                for flag in group.flags {
                    nextRows.append(.flag(flag, isLastInSection: flag.id == lastID))
                }
            }
            let rowsChanged = nextRows != rows
            let overridesChanged = overrides != self.overrides
            self.rows = nextRows
            self.overrides = overrides

            guard let tableView else { return }
            if rowsChanged {
                tableView.reloadData()
            } else if overridesChanged {
                let visible = tableView.rows(in: tableView.visibleRect)
                if visible.length > 0 {
                    let range = visible.location..<(visible.location + visible.length)
                    for rowIndex in range {
                        guard rows.indices.contains(rowIndex),
                            case .flag(let flag, let isLast) = rows[rowIndex],
                            let cell = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false)
                                as? FeatureFlagRowCell
                        else { continue }
                        cell.configure(
                            flag: flag,
                            currentOverride: overrides[flag.key],
                            showsDivider: !isLast
                        ) { [weak self] next in
                            self?.setOverride(next, flag)
                        }
                    }
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row) else { return 54 }
            switch rows[row] {
            case .header:
                return Self.headerHeight
            case .flag(let flag, _):
                let tableWidth = max(320, tableView.bounds.width)
                let widthBucket = Int((tableWidth / 16).rounded())
                if widthBucket != cachedWidthBucket {
                    cachedWidthBucket = widthBucket
                    cachedHeights.removeAll(keepingCapacity: true)
                }
                if let cached = cachedHeights[flag.key] {
                    return cached
                }
                let textWidth = max(120, tableWidth - FeatureFlagRowCell.buttonWidth - 36)
                let computed = FeatureFlagRowCell.preferredHeight(for: flag, textWidth: textWidth)
                cachedHeights[flag.key] = computed
                return computed
            }
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            false
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case .header(let category):
                let cell =
                    (tableView.makeView(withIdentifier: Self.headerIdentifier, owner: nil)
                        as? FeatureFlagSectionHeaderCell)
                    ?? FeatureFlagSectionHeaderCell(identifier: Self.headerIdentifier)
                cell.configure(title: category.title)
                return cell
            case .flag(let flag, let isLast):
                let cell =
                    (tableView.makeView(withIdentifier: Self.flagIdentifier, owner: nil) as? FeatureFlagRowCell)
                    ?? FeatureFlagRowCell(identifier: Self.flagIdentifier)
                cell.configure(
                    flag: flag,
                    currentOverride: overrides[flag.key],
                    showsDivider: !isLast
                ) { [weak self] next in
                    self?.setOverride(next, flag)
                }
                return cell
            }
        }
    }
}

@MainActor
private final class FeatureFlagSectionHeaderCell: NSTableCellView {
    private static let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .semibold)
    private var titleText = ""

    override var isFlipped: Bool { true }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        guard titleText != title else { return }
        titleText = title
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !titleText.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (titleText as NSString).draw(
            in: NSRect(x: 12, y: bounds.height - 20, width: max(0, bounds.width - 24), height: 16),
            withAttributes: attrs
        )
    }
}

@MainActor
private final class FeatureFlagRowCell: NSTableCellView {
    static let buttonWidth: CGFloat = 130
    private static let nameFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    private static let statusFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    private static let detailsFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    private static let keyFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
    private static let chevronImage = NSImage(
        systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
    private static let truncatingParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()
    private static let wrappingParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        return style
    }()

    private let stateButton = NSButton(title: "", target: nil, action: nil)
    private var flag: BrowserWebKitFeatureFlag?
    private var currentOverride: BrowserWebKitFeatureFlagOverride?
    private var stateButtonTitle = ""
    private var showsDivider = true
    private var onSelect: (@MainActor (BrowserWebKitFeatureFlagOverride?) -> Void)?

    override var isFlipped: Bool { true }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        stateButton.isBordered = false
        stateButton.title = ""
        stateButton.target = self
        stateButton.action = #selector(presentStateMenu)
        addSubview(stateButton)

        let contextMenu = NSMenu()
        let copyItem = NSMenuItem(
            title: String(localized: "Copy Flag Key"), action: #selector(copyKey), keyEquivalent: "")
        copyItem.target = self
        contextMenu.addItem(copyItem)
        menu = contextMenu
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let buttonFrame = NSRect(x: bounds.width - Self.buttonWidth - 12, y: 8, width: Self.buttonWidth, height: 24)
        if stateButton.frame != buttonFrame {
            stateButton.frame = buttonFrame
        }
    }

    func configure(
        flag: BrowserWebKitFeatureFlag,
        currentOverride: BrowserWebKitFeatureFlagOverride?,
        showsDivider: Bool,
        onSelect: @escaping @MainActor (BrowserWebKitFeatureFlagOverride?) -> Void
    ) {
        let textChanged = self.flag != flag || self.showsDivider != showsDivider
        self.flag = flag
        self.currentOverride = currentOverride
        self.showsDivider = showsDivider
        self.onSelect = onSelect

        let buttonTitle: String =
            switch currentOverride {
            case nil:
                flag.defaultValue ? String(localized: "Default (On)") : String(localized: "Default (Off)")
            case .enabled:
                String(localized: "Enabled")
            case .disabled:
                String(localized: "Disabled")
            }
        let titleChanged = stateButtonTitle != buttonTitle
        stateButtonTitle = buttonTitle
        if titleChanged {
            stateButton.setAccessibilityValue(buttonTitle)
        }
        if textChanged || titleChanged {
            stateButton.setAccessibilityLabel("State for \(flag.name)")
            setAccessibilityIdentifier("webkit-feature-\(flag.key)")
            needsDisplay = true
        }
    }

    private static let nameAttributes: [NSAttributedString.Key: Any] = [
        .font: nameFont,
        .foregroundColor: NSColor.labelColor,
    ]
    private static let statusAttributes: [NSAttributedString.Key: Any] = [
        .font: statusFont,
        .foregroundColor: NSColor.secondaryLabelColor,
    ]
    private static let detailsAttributes: [NSAttributedString.Key: Any] = [
        .font: detailsFont,
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: wrappingParagraph,
    ]
    private static let keyAttributes: [NSAttributedString.Key: Any] = [
        .font: keyFont,
        .foregroundColor: NSColor.tertiaryLabelColor,
    ]
    private static let buttonAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular),
        .foregroundColor: NSColor.labelColor,
    ]
    private static var statusWidths: [String: CGFloat] = [:]

    override func draw(_ dirtyRect: NSRect) {
        guard let flag, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let width = bounds.width
        let height = bounds.height
        let textX: CGFloat = 12
        let textMaxWidth = max(80, width - Self.buttonWidth - 36)

        let statusTitle = flag.status.title
        let statusWidth: CGFloat
        if let cached = Self.statusWidths[statusTitle] {
            statusWidth = cached
        } else {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: statusTitle, attributes: Self.statusAttributes))
            let measured = ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
            Self.statusWidths[statusTitle] = measured
            statusWidth = measured
        }
        let badgeWidth = min(96, statusWidth + 12)
        let maxNameWidth = max(40, textMaxWidth - badgeWidth - 6)

        let nameLine = Self.truncatedLine(flag.name, attributes: Self.nameAttributes, maxWidth: maxNameWidth)
        let naturalNameWidth = min(maxNameWidth, ceil(CTLineGetTypographicBounds(nameLine, nil, nil, nil)))
        Self.drawLine(nameLine, at: CGPoint(x: textX, y: 20), in: ctx)

        let pillRect = CGRect(x: textX + naturalNameWidth + 6, y: 8, width: badgeWidth, height: 16)
        ctx.saveGState()
        ctx.setFillColor(NSColor.quaternaryLabelColor.cgColor)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(pillPath)
        ctx.fillPath()
        ctx.restoreGState()

        let statusLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: statusTitle, attributes: Self.statusAttributes))
        Self.drawLine(statusLine, at: CGPoint(x: pillRect.minX + 6, y: pillRect.minY + 11.5), in: ctx)

        var y: CGFloat = 28
        if !flag.details.isEmpty {
            let detailsHeight = max(14, height - 48)
            Self.drawWrappedText(
                flag.details,
                attributes: Self.detailsAttributes,
                in: CGRect(x: textX, y: y, width: textMaxWidth, height: detailsHeight),
                context: ctx
            )
            y += detailsHeight + 3
        }

        let keyLine = Self.truncatedLine(flag.key, attributes: Self.keyAttributes, maxWidth: textMaxWidth)
        Self.drawLine(keyLine, at: CGPoint(x: textX, y: y + 10), in: ctx)

        // Draw lightweight native-styled pop-up control pill directly in CoreGraphics
        // so recycling cells avoids CoreUI Aqua NSButton bezel re-rasterization.
        let buttonRect = CGRect(x: width - Self.buttonWidth - 12, y: 8, width: Self.buttonWidth, height: 24)
        ctx.saveGState()
        let buttonPath = CGPath(roundedRect: buttonRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.addPath(buttonPath)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.75)
        ctx.addPath(buttonPath)
        ctx.strokePath()
        ctx.restoreGState()

        let buttonLabelLine = Self.truncatedLine(
            stateButtonTitle,
            attributes: Self.buttonAttributes,
            maxWidth: Self.buttonWidth - 28
        )
        Self.drawLine(buttonLabelLine, at: CGPoint(x: buttonRect.minX + 8, y: buttonRect.minY + 16), in: ctx)
        if let chevron = Self.chevronImage {
            chevron.draw(
                in: NSRect(x: buttonRect.maxX - 18, y: buttonRect.minY + 6, width: 11, height: 12),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.65
            )
        }

        if showsDivider {
            ctx.setFillColor(NSColor.separatorColor.cgColor)
            ctx.fill(CGRect(x: 12, y: height - 1, width: max(0, width - 12), height: 1))
        }
    }

    private static func truncatedLine(
        _ string: String, attributes: [NSAttributedString.Key: Any], maxWidth: CGFloat
    ) -> CTLine {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard width > maxWidth else { return line }
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(maxWidth), .end, ellipsis) ?? line
    }

    private static func drawLine(_ line: CTLine, at baselineOrigin: CGPoint, in ctx: CGContext) {
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = baselineOrigin
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func drawWrappedText(
        _ string: String,
        attributes: [NSAttributedString.Key: Any],
        in rect: CGRect,
        context ctx: CGContext
    ) {
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    @objc private func presentStateMenu() {
        guard let flag else { return }
        let menu = NSMenu()
        let defaultTitle = flag.defaultValue ? String(localized: "Default (On)") : String(localized: "Default (Off)")
        let choices: [(String, BrowserWebKitFeatureFlagOverride?)] = [
            (defaultTitle, nil),
            (String(localized: "Enabled"), .enabled),
            (String(localized: "Disabled"), .disabled),
        ]
        var selectedItem: NSMenuItem?
        for (title, choice) in choices {
            let item = FeatureFlagMenuItem(title: title) { [weak self] in
                self?.onSelect?(choice)
            }
            if choice == currentOverride {
                item.state = .on
                selectedItem = item
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: selectedItem, at: NSPoint(x: 0, y: stateButton.bounds.height), in: stateButton)
    }

    @objc private func copyKey() {
        guard let key = flag?.key, !key.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
    }

    static func preferredHeight(for flag: BrowserWebKitFeatureFlag, textWidth: CGFloat) -> CGFloat {
        var height: CGFloat = 52
        if !flag.details.isEmpty {
            let approxCharsPerLine = max(16, Int(textWidth / 6.2))
            let estimatedLines = max(1, (flag.details.count + approxCharsPerLine - 1) / approxCharsPerLine)
            height += CGFloat(estimatedLines) * 15 + 4
        }
        return max(52, height)
    }
}

@MainActor
private final class FeatureFlagMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}
