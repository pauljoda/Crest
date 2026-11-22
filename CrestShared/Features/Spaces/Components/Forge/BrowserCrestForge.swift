import SwiftUI

/// A Space's appearance: its crest or icon on the Space's own sidebar field,
/// beside the Space's Background and Accent, then palettes to take in one
/// tap, then its icon, a crest started from a house or a plain symbol or
/// emoji. More Customization holds the
/// rest: the sidebar's pattern and finish, and the parts of the crest.
struct BrowserCrestForge: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    /// The part of the crest More Customization shows.
    @Binding var step: BrowserCrestStudioStep
    /// The Space's name, for a page that doesn't already let a person edit it.
    var name: Binding<String>? = nil
    /// Whether More Customization lists the crest's parts, each opening on a
    /// page of its own, in place of the step bar: a phone has no room for six
    /// segments.
    var listsSteps = false
    /// Whether this is the whole page rather than one part's own page.
    var showsStepBar = true

    @State private var initialAppearance: SpaceBranding?
    @State private var history: [SpaceBranding] = []
    @State private var editingStart: SpaceBranding?
    /// The look Undo put back, which is not itself a change to remember.
    @State private var restoredBranding: SpaceBranding?
    @State private var showsMore = false

    private var context: BrowserCrestStudioContext {
        BrowserCrestStudioContext(
            branding: $branding,
            defaults: branding.startingLook ?? initialAppearance ?? branding,
            compact: false, previewBranding: editingStart)
    }

    private var isCrest: Bool { branding.iconStyle == .layeredCrest }

    var body: some View {
        BrowserSettingsPane(.spaces) {
            if showsStepBar {
                page
            } else {
                stepSections
            }
        }
        #if os(iOS)
            .modifier(
                BrowserCrestForgeStepPages(isEnabled: listsSteps) { step in
                    BrowserCrestForge(branding: $branding, symbol: $symbol, step: .constant(step), showsStepBar: false)
                        .navigationTitle(Text(step.title))
                        .navigationBarTitleDisplayMode(.inline)
                })
        #endif
        #if os(macOS)
            .environment(\.browserSettingsColumnWidth, BrowserCrestForgeMetrics.columnWidth)
        #endif
        .environment(
            \.crestStudioEditingChanged,
            BrowserCrestStudioEditingAction { editing in
                // A drag is one change to undo, and the galleries keep their
                // compositions while it runs.
                if editing {
                    if editingStart == nil { editingStart = branding }
                } else if let start = editingStart {
                    editingStart = nil
                    if start != branding { remember(start) }
                }
            }
        )
        .onAppear { if initialAppearance == nil { initialAppearance = branding } }
        .onChange(of: branding) { previous, current in
            if let restored = restoredBranding {
                restoredBranding = nil
                if current == restored { return }
            }
            guard editingStart == nil else { return }
            remember(previous)
        }
        .accessibilityIdentifier("space-customization-controls")
    }

    // MARK: - Page

    @ViewBuilder private var page: some View {
        Section {
            BrowserSpacePalettePicker(branding: $branding)
        } header: {
            stageHeader
        }
        Section {
            BrowserSpaceIconPicker(branding: $branding, symbol: $symbol)
        } header: {
            CrestSettingsSectionHeading(title: "Icon")
        }
        BrowserMoreCustomizationHeader(isExpanded: $showsMore)
        if showsMore {
            sidebarSections
            if isCrest {
                crestSections
            }
        }
    }

    /// The stage heads the page's first section, outside the grouped boxes,
    /// so the crest sits on the Space's field alone.
    private var stageHeader: some View {
        BrowserCrestForgeStage(
            branding: $branding, symbol: symbol, showsCrestColors: showsMore || !showsStepBar, name: name,
            canUndo: !history.isEmpty, shuffle: shuffle, undo: undo,
            openStep: { opened in
                step = opened
                showsMore = true
            }
        )
        .textCase(nil)
        .padding(.bottom, 4)
    }

    // MARK: - Sidebar

    @ViewBuilder private var sidebarSections: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(SpaceBannerPattern.all, id: \.self) { pattern in
                    patternChoice(pattern)
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("space-sidebar-patterns")
        } header: {
            CrestSettingsSectionHeading(title: "Sidebar")
        }
        Section {
            if branding.showsPattern {
                LabeledContent("Pattern color") {
                    CrestColorWell(
                        title: "Pattern color",
                        fill: Binding(
                            get: { branding.patternFill },
                            set: { fill in context.branding.editorUpdate { $0.patternFill = fill } }))
                }
            }
            BrowserCrestStudioSlider(title: "Intensity", value: context.setting(\.bannerStrength))
            BrowserCrestStudioSlider(title: "Readability fade", value: context.setting(\.readabilityFade))
            BrowserCrestStudioSlider(title: "Folder colors", value: context.setting(\.folderColorIntensity))
            BrowserCrestStudioSlider(
                title: "Texture", value: context.setting(\.textureStrength),
                readout: .percent(zero: "None", full: "Full"))
            textColor
        }
    }

    private func patternChoice(_ pattern: SpaceBannerPattern) -> some View {
        let isWorn =
            branding.themeMode == .gradient
            ? pattern == .solid : branding.bannerPattern == pattern
        return BrowserCrestStudioChoice(title: pattern.title, selected: isWorn) {
            context.branding.editorUpdate { $0.wearPattern(pattern) }
        } artwork: {
            BrowserSpaceBannerBackground(branding: context.preview { $0.wearPattern(pattern) })
                .frame(width: 56, height: 48)
                .clipShape(.rect(cornerRadius: 8))
        }
    }

    private var textColor: some View {
        let text = context.setting(\.textColorMode)
        return CrestSettingRow("Text", setting: text.resettable("Text")) {
            Picker("Text", selection: text.binding) {
                ForEach(SpaceTextColorMode.all, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
                .fixedSize()
            #endif
        }
    }

    // MARK: - Crest

    @ViewBuilder private var crestSections: some View {
        if listsSteps {
            Section {
                ForEach(BrowserCrestStudioStep.all) { step in
                    NavigationLink(value: step) {
                        LabeledContent {
                            Text(step.summary(branding))
                        } label: {
                            Label {
                                Text(step.title)
                            } icon: {
                                Image(systemName: step.symbol)
                            }
                        }
                    }
                    .accessibilityIdentifier("space-forge-step-\(step.name)")
                }
                spaceColorsRow
            } header: {
                CrestSettingsSectionHeading(title: "Crest")
            }
        } else {
            stepSections
            Section { spaceColorsRow }
        }
    }

    /// Gives a crest with colors of its own the Space's back.
    @ViewBuilder private var spaceColorsRow: some View {
        if !branding.crestFollowsSpace {
            LabeledContent("The crest has colors of its own.") {
                Button("Use Space Colors") {
                    context.branding.editorUpdate { $0.followSpaceColors() }
                }
            }
        }
    }

    /// The part of the crest chosen, under the crest's heading and step bar,
    /// or on its own page under the stage.
    @ViewBuilder private var stepSections: some View {
        switch step.kind {
        case .shape:
            crestGallery(\.backplate, CrestBackplate.offered)
        case .field:
            crestGallery(\.fieldDivision, CrestFieldDivision.offered)
        case .band:
            crestGallery(\.ordinary, CrestOrdinary.offered)
        case .emblem:
            Section {
                BrowserCrestStudioEmblem(context: context, symbol: symbol)
            } header: {
                stepHeader
            }
        case .border:
            crestGallery(\.trim, CrestTrim.offered)
        case .finish:
            finishGallery
        }
    }

    private var stepHeader: some View {
        Group {
            if showsStepBar {
                VStack(alignment: .leading, spacing: 10) {
                    CrestSettingsSectionHeading(title: "Crest")
                    BrowserPlatformCrestForgeStepBar(step: $step, disabledSteps: [])
                }
            } else {
                stageHeader
            }
        }
        .textCase(nil)
    }

    private var finishGallery: some View {
        gallery(BrowserCrestFinishChoice.all, id: \.self) { choice in
            BrowserCrestStudioChoice(title: choice.title, selected: choice.isWorn(by: branding.crest)) {
                context.branding.editorUpdate {
                    $0.crest = choice.applying(to: $0.crest)
                    $0.hasCustomAppearance = true
                }
            } artwork: {
                crest(context.preview { $0.crest = choice.applying(to: $0.crest) })
            }
        }
    }

    private func crestGallery<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ path: WritableKeyPath<SpaceCrest, Option>, _ offered: [Option]
    ) -> some View {
        let value = context.crest(path)
        // A crest wearing a part no longer offered keeps it among the choices.
        let options = offered.contains(value.wrappedValue) ? offered : offered + [value.wrappedValue]
        return gallery(options, id: \.self) { option in
            BrowserCrestStudioChoice(title: option.title, selected: option == value.wrappedValue) {
                value.binding.wrappedValue = option
            } artwork: {
                crest(context.preview { $0.crest[keyPath: path] = option })
            }
        }
    }

    private func gallery<Item, ID: Hashable, Tile: View>(
        _ items: [Item], id: KeyPath<Item, ID>, @ViewBuilder tile: @escaping (Item) -> Tile
    ) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(items, id: id) { item in tile(item) }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("space-forge-gallery")
        } header: {
            stepHeader
        }
    }

    private func crest(_ look: SpaceBranding) -> some View {
        BrowserSpaceCrestIcon(branding: look, size: BrowserCrestForgeMetrics.tileCrestSize, rasterizesLayers: false)
            .equatable()
    }

    // MARK: - History

    private func remember(_ previous: SpaceBranding) {
        history.append(previous)
        if history.count > BrowserCrestForgeHistory.limit { history.removeFirst() }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        restoredBranding = previous
        branding = previous
    }

    private func shuffle() {
        branding = Self.shuffled(branding)
    }

    // MARK: - Looks

    /// A new crest and colors, every part chosen afresh from the ones More
    /// Customization offers: a dark tincture for the Background, a light one
    /// for the Accent, sometimes running on into the colors the harmony adds,
    /// and the crest in the Space's colors.
    static func shuffled(_ branding: SpaceBranding) -> SpaceBranding {
        let tinctures = Tincture.all.map(\.color)
        guard let dark = tinctures.filter({ $0.luminance < 0.3 }).randomElement(),
            let light = tinctures.filter({ $0.luminance > 0.42 }).randomElement()
        else { return branding }
        let chance = { (odds: Double) in Double.random(in: 0..<1) < odds }
        let run = { (color: BrandColor) in
            chance(0.5)
                ? CrestColorFill(
                    [color, CrestColorHarmony.run(beside: color)[0]], degrees: Double(Int.random(in: 0..<8) * 45))
                : CrestColorFill(color)
        }

        var look = branding
        look.iconStyle = .layeredCrest
        var crest = look.crest
        crest.backplate = CrestBackplate.offered.randomElement() ?? .shield
        crest.fieldDivision = chance(0.5) ? .plain : CrestFieldDivision.offered.filter { $0 != .plain }.randomElement()!
        crest.ordinary = chance(0.5) ? .none : CrestOrdinary.offered.filter { $0 != .none }.randomElement()!
        crest.symbol = CrestSymbol.selectable.randomElement() ?? .dragon
        crest.charge = nil
        crest.chargeLayout = chance(0.75) ? .single : [.paired, .trio].randomElement()!
        crest.trim = CrestTrim.offered.randomElement() ?? .none
        crest = (BrowserCrestFinishChoice.all.randomElement() ?? .shadow).applying(to: crest)
        look.crest = crest
        look.followSpaceColors()
        look.wearPattern(.solid)
        look.backgroundFill = run(dark)
        look.accentFill = run(light)
        look.hasCustomAppearance = true
        return look.normalized()
    }
}

private enum BrowserCrestForgeHistory {
    static let limit = 40
}

#if os(iOS)
    /// Opens a listed part on a page of its own, where More Customization
    /// lists the crest's parts.
    private struct BrowserCrestForgeStepPages<Page: View>: ViewModifier {
        let isEnabled: Bool
        @ViewBuilder let page: (BrowserCrestStudioStep) -> Page

        func body(content: Content) -> some View {
            if isEnabled {
                content.navigationDestination(for: BrowserCrestStudioStep.self, destination: page)
            } else {
                content
            }
        }
    }
#endif
