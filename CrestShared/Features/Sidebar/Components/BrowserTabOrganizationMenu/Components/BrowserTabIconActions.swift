import SwiftUI

struct BrowserTabIconActions: View {
    let tab: BrowserTab
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let performIfCurrent: ((BrowserTab) -> Void) -> Void
    let clearIcon: (BrowserTab) -> Void
    let changeIcon: (BrowserTab) -> Void

    var body: some View {
        Button("Pull New Icon", systemImage: "arrow.clockwise.circle") {
            performIfCurrent { _ in pullNewIcon?() }
        }
        .disabled(!isLoaded || pullNewIcon == nil)

        Button("Clear Icon", systemImage: "xmark.circle") {
            performIfCurrent(clearIcon)
        }
        .disabled(tab.iconMode == .automatic && tab.faviconData == nil)

        Button("Change Icon…", systemImage: "face.smiling") {
            performIfCurrent(changeIcon)
        }
    }
}

/// A system symbol offered by the shared entity-icon picker. Tabs and split
/// groups currently accept emoji overrides, while Spaces supply these choices
/// too; the picker stays one component without pretending every entity has the
/// same storage vocabulary.
struct BrowserIconSystemChoice: Identifiable {
    let symbol: String
    let title: LocalizedStringKey

    var id: String { symbol }
}

/// Everything a visible icon needs to become the source of its own picker.
/// Keeping the presentation with the artwork, instead of with the surrounding
/// row or overflow menu, gives SwiftUI the real source rect to keep its popover
/// arrow and edge avoidance correct.
struct BrowserIconCustomizationPresentation {
    let isPresented: Binding<Bool>
    let title: LocalizedStringKey
    let currentEmoji: String?
    var currentSystemSymbol: String? = nil
    var systemSymbols: [BrowserIconSystemChoice] = []
    var showsReset = false
    var resetTitle: LocalizedStringKey? = nil
    let setEmoji: (String) -> Void
    var setSystemSymbol: ((String) -> Void)? = nil
    var reset: (() -> Void)? = nil
}

enum BrowserTabIconCustomizationPolicy {
    /// A website favicon is the automatic state, not a customization. Only an
    /// emoji or deliberately pulled icon earns the reset affordance.
    static func showsReset(for tab: BrowserTab) -> Bool {
        tab.iconMode != .automatic
    }
}

enum BrowserIconPopoverPlacementPolicy {
    /// Compact horizontal geometry needs the system's default vertical
    /// placement so the popover can flip above or below its icon. A forced
    /// side arrow can squeeze the picker into the narrow strip beside a phone
    /// sidebar. Regular geometry keeps the caller's preferred side anchor.
    static func preferredArrowEdge(
        horizontalSizeClass: UserInterfaceSizeClass?,
        regularArrowEdge: Edge
    ) -> Edge? {
        horizontalSizeClass == .compact ? nil : regularArrowEdge
    }
}

extension View {
    func browserIconCustomizationPopover(
        _ presentation: BrowserIconCustomizationPresentation,
        arrowEdge: Edge = .trailing
    ) -> some View {
        modifier(
            BrowserIconCustomizationPopoverModifier(
                presentation: presentation,
                arrowEdge: arrowEdge
            )
        )
    }
}

private struct BrowserIconCustomizationPopoverModifier: ViewModifier {
    let presentation: BrowserIconCustomizationPresentation
    let arrowEdge: Edge

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if let preferredArrowEdge =
            BrowserIconPopoverPlacementPolicy.preferredArrowEdge(
                horizontalSizeClass: horizontalSizeClass,
                regularArrowEdge: arrowEdge
            )
        {
            content.popover(
                isPresented: presentation.isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: preferredArrowEdge
            ) {
                popoverContent
            }
        } else {
            content.popover(
                isPresented: presentation.isPresented,
                attachmentAnchor: .rect(.bounds)
            ) {
                popoverContent
            }
        }
    }

    private var popoverContent: some View {
        BrowserIconCustomizationView(
            title: presentation.title,
            currentEmoji: presentation.currentEmoji,
            currentSystemSymbol: presentation.currentSystemSymbol,
            systemSymbols: presentation.systemSymbols,
            showsReset: presentation.showsReset,
            resetTitle: presentation.resetTitle,
            setEmoji: presentation.setEmoji,
            setSystemSymbol: presentation.setSystemSymbol,
            reset: presentation.reset
        )
        .presentationCompactAdaptation(.popover)
    }
}

/// One compact native-popover surface shared by tabs, Spaces, and split
/// groups. Its catalog is a fast browsable path, while the focused native text
/// client remains the insertion target for any complete emoji grapheme the
/// system Character Viewer, keyboard, or pasteboard can produce.
struct BrowserIconCustomizationView: View {
    let title: LocalizedStringKey
    let currentEmoji: String?
    var currentSystemSymbol: String? = nil
    var systemSymbols: [BrowserIconSystemChoice] = []
    var showsReset = false
    var resetTitle: LocalizedStringKey? = nil
    let setEmoji: (String) -> Void
    var setSystemSymbol: ((String) -> Void)? = nil
    var reset: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = BrowserIconPickerMode.emoji
    @State private var category = BrowserEmojiCategory.people
    @State private var query = ""
    @State private var variantChoice: BrowserTabEmojiChoice?
    #if os(macOS)
        @State private var nativeTextInput = BrowserNativeEmojiTextInputController()
    #else
        @FocusState private var isEmojiFocused: Bool
    #endif

    private let contentWidth: CGFloat = 284
    private let gridSpacing = CrestSpacing.extraSmall

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            header
            searchField
            selectionGrid
            if mode == .emoji, query.isEmpty {
                categoryBar
            }
        }
        .padding(CrestSpacing.large)
        .frame(width: contentWidth + CrestSpacing.large * 2)
        .animation(resetAnimation, value: showsReset)
        .onAppear(perform: repairMode)
        .onChange(of: query, handlePotentialEmojiInsertion)
        .onChange(of: currentEmoji) { _, _ in repairMode() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-icon-picker")
    }

    private var header: some View {
        HStack(spacing: CrestSpacing.small) {
            if systemSymbols.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Icon Type", selection: $mode) {
                    Text("Emoji").tag(BrowserIconPickerMode.emoji)
                    Text("Icon").tag(BrowserIconPickerMode.systemSymbol)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if showsReset, let resetTitle, let reset {
                Button {
                    query = ""
                    reset()
                } label: {
                    Image(systemName: "trash")
                        .frame(
                            width: CrestLayout.minimumHitTarget,
                            height: CrestLayout.minimumHitTarget
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .transition(.scale(scale: 0.72).combined(with: .opacity))
                .help(Text(resetTitle))
                .accessibilityLabel(Text(resetTitle))
                .accessibilityIdentifier("browser-icon-picker-reset")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if mode == .emoji {
                emojiSearchField
            } else {
                TextField("Search Icons", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("browser-icon-search-field")
            }

            if mode == .emoji {
                Button(
                    BrowserNativeEmojiPickerPresentation.current.actionTitle,
                    systemImage: "face.smiling",
                    action: presentNativeEmojiPicker
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(
                    width: CrestLayout.minimumHitTarget,
                    height: CrestLayout.minimumHitTarget
                )
                .contentShape(.rect)
                .accessibilityHint(
                    "Inserts any emoji through the system text input experience."
                )
            }
        }
        .padding(.leading, CrestSpacing.small)
        .padding(.trailing, CrestSpacing.extraSmall)
        .frame(minHeight: CrestLayout.minimumHitTarget)
        .background(.quaternary, in: .rect(cornerRadius: CrestRadius.control))
        .onChange(of: mode) { _, _ in query = "" }
    }

    @ViewBuilder
    private var emojiSearchField: some View {
        #if os(macOS)
            BrowserNativeEmojiTextField(
                text: $query,
                placeholder: "Search or Enter Emoji",
                controller: nativeTextInput,
                commit: commitInsertedEmoji
            )
            .frame(height: 22)
        #else
            TextField("Search or Enter Emoji", text: $query)
                .textFieldStyle(.plain)
                .focused($isEmojiFocused)
                .submitLabel(.done)
                .onSubmit(commitInsertedEmoji)
                .accessibilityIdentifier("browser-emoji-icon-field")
        #endif
    }

    @ViewBuilder
    private var selectionGrid: some View {
        if visibleChoiceCount == 0 {
            Text(mode == .emoji ? "No Matching Emoji" : "No Matching Icons")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: contentWidth, height: 72)
                .accessibilityIdentifier("browser-icon-picker-empty")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    if mode == .emoji {
                        ForEach(visibleEmojiChoices) { choice in
                            emojiButton(choice)
                        }
                    } else {
                        ForEach(visibleSystemSymbols) { choice in
                            systemSymbolButton(choice)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: contentWidth, height: gridHeight)
        }
    }

    private var categoryBar: some View {
        VStack(spacing: CrestSpacing.small) {
            Divider()
                .padding(.horizontal, CrestSpacing.extraSmall)

            ScrollView(.horizontal) {
                HStack(spacing: CrestSpacing.extraSmall) {
                    ForEach(BrowserEmojiCategory.allCases) { option in
                        Button {
                            category = option
                        } label: {
                            Image(systemName: option.systemImage)
                                .frame(
                                    width: CrestLayout.minimumHitTarget,
                                    height: CrestLayout.minimumHitTarget
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            category == option
                                ? Color.accentColor : Color.secondary
                        )
                        .background(
                            category == option ? CrestColor.hover : .clear,
                            in: .rect(cornerRadius: CrestRadius.compact)
                        )
                        .help(Text(option.title))
                        .accessibilityLabel(Text(option.title))
                        .accessibilityValue(
                            category == option ? "Selected" : ""
                        )
                    }
                }
                .frame(
                    minWidth: contentWidth - CrestSpacing.small * 2,
                    alignment: .center
                )
            }
            .contentMargins(
                .horizontal,
                CrestSpacing.small,
                for: .scrollContent
            )
            .scrollIndicators(.hidden)
        }
        .frame(width: contentWidth)
        .accessibilityIdentifier("browser-emoji-category-bar")
    }

    @ViewBuilder
    private func emojiButton(_ choice: BrowserTabEmojiChoice) -> some View {
        let button = Button {
            selectEmoji(choice.emoji)
        } label: {
            Text(choice.emoji)
                .font(.title3)
                .frame(width: cellSize, height: cellSize)
                .contentShape(.rect)
        }
        .background(
            currentEmoji == choice.emoji ? CrestColor.hover : .clear,
            in: .rect(cornerRadius: CrestRadius.compact)
        )
        .help(choice.name)
        .accessibilityLabel(choice.name)
        .accessibilityValue(currentEmoji == choice.emoji ? "Selected" : "")

        if choice.variants.isEmpty {
            button.buttonStyle(.plain)
        } else {
            #if canImport(UIKit)
                button
                    .buttonStyle(
                        BrowserEmojiVariantButtonStyle {
                            variantChoice = choice
                        }
                    )
                    .popover(
                        isPresented: variantPopoverBinding(for: choice),
                        attachmentAnchor: .rect(.bounds)
                    ) {
                        BrowserEmojiVariantPicker(
                            variants: choice.variants,
                            selectEmoji: selectEmojiVariant
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                    .accessibilityAction(named: "Show Emoji Variations") {
                        variantChoice = choice
                    }
                    .accessibilityHint(
                        "Long press to choose a skin tone variation."
                    )
            #else
                button
                    .buttonStyle(.plain)
                    .contextMenu {
                        ForEach(choice.variants) { variant in
                            Button {
                                selectEmoji(variant.emoji)
                            } label: {
                                Label {
                                    Text(variant.name)
                                } icon: {
                                    Text(variant.emoji)
                                }
                            }
                        }
                    }
                    .accessibilityHint(
                        "Long press or open the context menu for skin tone variations."
                    )
            #endif
        }
    }

    private func systemSymbolButton(
        _ choice: BrowserIconSystemChoice
    ) -> some View {
        Button {
            query = ""
            mode = .systemSymbol
            setSystemSymbol?(choice.symbol)
        } label: {
            Image(systemName: choice.symbol)
                .font(.title3)
                .frame(width: cellSize, height: cellSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            currentSystemSymbol == choice.symbol ? CrestColor.hover : .clear,
            in: .rect(cornerRadius: CrestRadius.compact)
        )
        .help(Text(choice.title))
        .accessibilityLabel(Text(choice.title))
        .accessibilityValue(
            currentSystemSymbol == choice.symbol ? "Selected" : ""
        )
    }

    private var visibleEmojiChoices: [BrowserTabEmojiChoice] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? BrowserTabEmojiChoices.choices(in: category)
            : BrowserTabEmojiChoices.matching(query)
    }

    private var visibleSystemSymbols: [BrowserIconSystemChoice] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return systemSymbols }
        return systemSymbols.filter {
            $0.symbol.localizedStandardContains(trimmed)
        }
    }

    private var visibleChoiceCount: Int {
        mode == .emoji
            ? visibleEmojiChoices.count
            : visibleSystemSymbols.count
    }

    private var cellSize: CGFloat {
        max(CrestLayout.minimumHitTarget, 32)
    }

    private var columnCount: Int {
        max(
            Int((contentWidth + gridSpacing) / (cellSize + gridSpacing)),
            1
        )
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(cellSize), spacing: gridSpacing),
            count: columnCount
        )
    }

    private var gridHeight: CGFloat {
        let rows = max(
            Int(ceil(Double(visibleChoiceCount) / Double(columnCount))),
            1
        )
        let visibleRows = min(rows, 4)
        return CGFloat(visibleRows) * cellSize
            + CGFloat(visibleRows - 1) * gridSpacing
    }

    private var resetAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.collection,
            reduceMotion: reduceMotion
        )
    }

    private func repairMode() {
        guard !systemSymbols.isEmpty else {
            mode = .emoji
            return
        }
        mode = currentEmoji == nil ? .systemSymbol : .emoji
    }

    private func handlePotentialEmojiInsertion(
        _ oldValue: String,
        _ newValue: String
    ) {
        guard mode == .emoji,
            let emoji = BrowserIconSymbol.normalizedEmoji(newValue)
        else { return }
        setEmoji(emoji)
        query = ""
    }

    private func commitInsertedEmoji() {
        guard let emoji = BrowserIconSymbol.normalizedEmoji(query) else {
            return
        }
        setEmoji(emoji)
        query = ""
    }

    private func selectEmoji(_ emoji: String) {
        query = ""
        mode = .emoji
        setEmoji(emoji)
    }

    private func variantPopoverBinding(
        for choice: BrowserTabEmojiChoice
    ) -> Binding<Bool> {
        Binding(
            get: { variantChoice?.id == choice.id },
            set: { isPresented in
                if !isPresented, variantChoice?.id == choice.id {
                    variantChoice = nil
                }
            }
        )
    }

    private func selectEmojiVariant(_ emoji: String) {
        variantChoice = nil
        selectEmoji(emoji)
    }

    private func presentNativeEmojiPicker() {
        #if os(macOS)
            nativeTextInput.presentCharacterPalette()
        #else
            isEmojiFocused = true
        #endif
    }
}

#if canImport(UIKit)
    private struct BrowserEmojiVariantButtonStyle: PrimitiveButtonStyle {
        let showVariants: () -> Void

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(.rect)
                .gesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .exclusively(before: TapGesture())
                        .onEnded { value in
                            switch value {
                            case .first:
                                showVariants()
                            case .second:
                                configuration.trigger()
                            }
                        }
                )
        }
    }

    enum BrowserEmojiVariantPickerMetrics {
        static let columnCount = 3
        static let cellSize = CrestLayout.minimumHitTarget
        static let spacing = CrestSpacing.extraSmall

        static func contentWidth(for variantCount: Int) -> CGFloat {
            let columns = min(max(variantCount, 1), columnCount)
            return CGFloat(columns) * cellSize
                + CGFloat(columns - 1) * spacing
        }
    }

    private struct BrowserEmojiVariantPicker: View {
        let variants: [BrowserTabEmojiVariant]
        let selectEmoji: (String) -> Void

        private var columns: [GridItem] {
            Array(
                repeating: GridItem(
                    .fixed(BrowserEmojiVariantPickerMetrics.cellSize),
                    spacing: BrowserEmojiVariantPickerMetrics.spacing
                ),
                count: min(
                    max(variants.count, 1),
                    BrowserEmojiVariantPickerMetrics.columnCount
                )
            )
        }

        var body: some View {
            LazyVGrid(
                columns: columns,
                spacing: BrowserEmojiVariantPickerMetrics.spacing
            ) {
                ForEach(variants) { variant in
                    Button {
                        selectEmoji(variant.emoji)
                    } label: {
                        Text(variant.emoji)
                            .font(.title3)
                            .frame(
                                width: BrowserEmojiVariantPickerMetrics.cellSize,
                                height: BrowserEmojiVariantPickerMetrics.cellSize
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(variant.name)
                }
            }
            .frame(
                width: BrowserEmojiVariantPickerMetrics.contentWidth(
                    for: variants.count
                )
            )
            .padding(CrestSpacing.medium)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("browser-emoji-variant-picker")
        }
    }
#endif

private enum BrowserIconPickerMode: Hashable {
    case emoji
    case systemSymbol
}

enum BrowserNativeEmojiPickerPresentation: Equatable, Sendable {
    case characterPalette
    case focusedTextInput

    static var current: Self {
        #if os(macOS)
            .characterPalette
        #else
            .focusedTextInput
        #endif
    }

    var actionTitle: LocalizedStringKey {
        switch self {
        case .characterPalette: "Open Emoji Picker"
        case .focusedTextInput: "Use Emoji Keyboard"
        }
    }
}
