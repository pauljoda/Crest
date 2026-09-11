import SwiftUI

struct BrowserCrestStudioComposition: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    private var preview: BrowserSpaceBranding? { context.compact ? context.value : nil }

    var body: some View {
        BrowserCrestStudioGroup(title: "Shape", preview: preview, symbol: symbol) {
            gallery("Plate", \.backplate, BrowserSpaceCrestBackplate.allCases)
            if context.value.crest.backplate == .seal {
                context.count("Teeth", \.sealTeeth, range: 6...24)
            }
            context.slider("Edge weight", \.edgeWidth)
            BrowserCrestStudioColorRow(context: context, title: "Edge & outline", path: \.edgeColorIndex)
            context.slider("Plate size", \.plateScale, range: BrowserSpaceCrest.plateScaleRange)
        }
        BrowserCrestStudioGroup(title: "Field", preview: preview, symbol: symbol) {
            gallery("Division", \.fieldDivision, BrowserSpaceCrestFieldDivision.allCases)
            BrowserCrestStudioColorRow(context: context, title: "Field color", path: \.backplateColorIndex)
            if context.value.crest.fieldDivision != .plain {
                BrowserCrestStudioColorRow(context: context, title: "Second field", path: \.secondaryFieldColorIndex)
            }
            if context.value.crest.fieldDivision.isCounted {
                context.count("Repeats", \.divisionCount, range: BrowserSpaceCrest.divisionCountRange)
            }
            context.picker("Finish", \.finish, options: BrowserSpaceCrestFinish.allCases)
            if context.value.crest.finish == .sheen {
                context.slider("Sheen angle", \.sheenAngle, range: 0...360, readout: .init { "\(Int($0))°" })
            }
        }
    }

    private func gallery<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<BrowserSpaceCrest, Option>, _ options: [Option]
    ) -> some View {
        BrowserCrestStudioGallery(context: context, title: title, path: path, options: options)
    }
}

struct BrowserCrestStudioOrnaments: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    private var preview: BrowserSpaceBranding? { context.compact ? context.value : nil }

    var body: some View {
        BrowserCrestStudioGroup(title: "Band", preview: preview, symbol: symbol) {
            BrowserCrestStudioGallery(
                context: context, title: "Design", path: \.ordinary, options: BrowserSpaceCrestOrdinary.allCases)
            if context.value.crest.ordinary != .none {
                BrowserCrestStudioColorRow(context: context, title: "Band color", path: \.ordinaryColorIndex)
                context.slider("Width", \.ordinaryWidth, range: BrowserSpaceCrest.ordinaryWidthRange)
            }
        }
        BrowserCrestStudioGroup(title: "Border", preview: preview, symbol: symbol) {
            BrowserCrestStudioGallery(
                context: context, title: "Design", path: \.trim, options: BrowserSpaceCrestTrim.allCases)
            if context.value.crest.trim != .none {
                BrowserCrestStudioColorRow(context: context, title: "Border color", path: \.trimColorIndex)
                context.slider("Weight", \.trimWeight, range: BrowserSpaceCrest.trimWeightRange)
            }
            if context.value.crest.trim.isCounted {
                context.count("Details", \.trimDetail, range: BrowserSpaceCrest.trimDetailRange)
            }
        }
        BrowserCrestStudioGroup(title: "Depth", preview: preview, symbol: symbol) {
            context.picker("Shadow", \.depth, options: BrowserSpaceCrestDepth.allCases)
            let outline = context.crest(\.showsOutline)
            CrestSettingRow("Outline", setting: outline.resettable("Outline")) {
                Toggle("Outline", isOn: outline.binding).labelsHidden()
            }
            if outline.wrappedValue {
                BrowserCrestStudioColorRow(context: context, title: "Edge & outline", path: \.edgeColorIndex)
            }
        }
    }
}
