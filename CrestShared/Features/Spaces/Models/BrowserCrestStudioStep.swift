import SwiftUI

/// The steps of making a crest, in the order arms are composed: the Forge's
/// step bar on the Mac, and the Studio's groups everywhere. Each step carries
/// the sections of choices the Forge shows for it.
struct BrowserCrestStudioStep: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let start = BrowserCrestStudioStep(
        name: "start", title: "Start from", symbol: "sparkles", isCrestOnly: false,
        summary: { branding in SpaceHouse.all.first { $0.isWorn(by: branding) }?.title ?? "Custom" },
        sections: { forge in
            AnyView(
                forge.gallery(SpaceHouse.all, id: \.self) { house in
                    BrowserCrestStudioChoice(
                        title: house.title, selected: house.isWorn(by: forge.branding), tint: .accentColor
                    ) {
                        forge.branding = house.applying(to: forge.branding)
                    } artwork: {
                        forge.crest(house.applying(to: forge.editingStart ?? forge.branding))
                    }
                })
        })
    static let shape = BrowserCrestStudioStep(
        name: "shape", title: "Shape", symbol: "shield", isCrestOnly: true,
        summary: { $0.crest.backplate.title },
        sections: { forge in
            AnyView(
                Group {
                    forge.crestGallery(\.backplate, CrestBackplate.all)
                    Section {
                        forge.context.slider("Edge", \.edgeWidth, range: CrestMeasure.edgeWidth.range)
                        forge.context.slider("Size", \.plateScale, range: CrestMeasure.plateScale.range)
                        if forge.branding.crest.backplate.hasTeeth {
                            forge.context.count("Teeth", \.sealTeeth, range: CrestMeasure.sealTeeth.countRange)
                        }
                    }
                })
        })
    static let field = BrowserCrestStudioStep(
        name: "field", title: "Field", symbol: "square.grid.2x2", isCrestOnly: true,
        summary: { $0.crest.fieldDivision.title },
        sections: { forge in
            AnyView(
                Group {
                    forge.crestGallery(\.fieldDivision, CrestFieldDivision.all)
                    Section {
                        forge.context.count("Repeats", \.divisionCount, range: CrestMeasure.divisionCount.countRange)
                            .disabled(!forge.branding.crest.fieldDivision.isCounted)
                    }
                })
        })
    static let band = BrowserCrestStudioStep(
        name: "band", title: "Band", symbol: "rectangle.center.inset.filled", isCrestOnly: true,
        summary: { $0.crest.ordinary.title },
        sections: { forge in
            AnyView(
                Group {
                    forge.crestGallery(\.ordinary, CrestOrdinary.all)
                    Section {
                        forge.context.slider("Width", \.ordinaryWidth, range: CrestMeasure.ordinaryWidth.range)
                            .disabled(forge.branding.crest.ordinary == .none)
                    }
                })
        })
    static let emblem = BrowserCrestStudioStep(
        name: "emblem", title: "Emblem", symbol: "seal", isCrestOnly: false,
        summary: { branding in
            guard branding.iconStyle == .layeredCrest else { return "Icon" }
            let charge = branding.crest.resolvedCharge
            return charge.kind == .heraldic ? (charge.symbol ?? branding.crest.symbol).title : charge.kind.title
        },
        sections: { forge in
            AnyView(
                Group {
                    Section {
                        forge.identityRow
                    } header: {
                        forge.stageHeader
                    }
                    if forge.isIcon {
                        forge.iconSections
                    } else {
                        Section {
                            BrowserCrestStudioEmblem(context: forge.context, symbol: forge.symbol, isEmbedded: true)
                        }
                    }
                })
        })
    static let border = BrowserCrestStudioStep(
        name: "border", title: "Border", symbol: "square.dashed", isCrestOnly: true,
        summary: { $0.crest.trim.title },
        sections: { forge in
            AnyView(
                Group {
                    forge.crestGallery(\.trim, CrestTrim.all)
                    Section {
                        forge.context.slider("Weight", \.trimWeight, range: CrestMeasure.trimWeight.range)
                            .disabled(forge.branding.crest.trim == .none)
                        forge.context.count("Details", \.trimDetail, range: CrestMeasure.trimDetail.countRange)
                            .disabled(!forge.branding.crest.trim.isCounted)
                    }
                })
        })
    static let finish = BrowserCrestStudioStep(
        name: "finish", title: "Finish", symbol: "light.max", isCrestOnly: true,
        summary: { $0.crest.finish.title },
        sections: { forge in
            AnyView(
                Group {
                    forge.crestGallery(\.finish, CrestFinish.all)
                    Section {
                        forge.segmented("Shadow", forge.context.crest(\.depth), options: CrestDepth.all)
                        let outline = forge.context.crest(\.showsOutline)
                        CrestSettingRow("Outline", setting: outline.resettable("Outline")) {
                            Toggle("Outline", isOn: outline.binding).labelsHidden()
                        }
                        if forge.branding.crest.finish.hasAngle {
                            forge.context.slider(
                                "Sheen angle", \.sheenAngle, range: CrestMeasure.sheenAngle.range,
                                readout: .init { "\(Int($0))°" })
                        }
                    }
                })
        })
    static let sidebar = BrowserCrestStudioStep(
        name: "sidebar", title: "Sidebar", symbol: "sidebar.left", isCrestOnly: false,
        summary: { $0.themeMode == .gradient ? "Gradient" : $0.bannerPattern.title },
        sections: { forge in
            AnyView(
                Group {
                    forge.sidebarGallery
                    forge.sidebarSection
                })
        })

    /// Every step, in the step bar's order.
    static let all: [BrowserCrestStudioStep] = [start, shape, field, band, emblem, border, finish, sidebar]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String

    /// Whether the step shapes only a crest, so an icon has no use for it.
    let isCrestOnly: Bool

    /// What a branding has chosen at this step, in a word or two.
    let summary: @Sendable (SpaceBranding) -> LocalizedStringResource

    /// The sections of choices the Forge shows for the step.
    let sections: @MainActor @Sendable (BrowserCrestForge) -> AnyView

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String, isCrestOnly: Bool,
        summary: @escaping @Sendable (SpaceBranding) -> LocalizedStringResource,
        sections: @escaping @MainActor @Sendable (BrowserCrestForge) -> AnyView
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.isCrestOnly = isCrestOnly
        self.summary = summary
        self.sections = sections
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCrestStudioStep, rhs: BrowserCrestStudioStep) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
