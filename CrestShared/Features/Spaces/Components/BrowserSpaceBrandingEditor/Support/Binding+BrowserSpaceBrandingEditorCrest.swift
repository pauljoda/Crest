import SwiftUI

extension Binding where Value == BrowserSpaceBranding {
    var editorBackplateColorIndex: Binding<Int> {
        editorCrestBinding(
            get: { $0.backplateColorIndex },
            set: { $0.backplateColorIndex = $1 }
        )
    }

    var editorSecondaryFieldColorIndex: Binding<Int> {
        editorCrestBinding(
            get: { $0.secondaryFieldColorIndex },
            set: { $0.secondaryFieldColorIndex = $1 }
        )
    }

    var editorOrdinaryColorIndex: Binding<Int> {
        editorCrestBinding(
            get: { $0.ordinaryColorIndex },
            set: { $0.ordinaryColorIndex = $1 }
        )
    }

    var editorChargeLayout: Binding<BrowserSpaceCrestChargeLayout> {
        editorCrestBinding(
            get: { $0.chargeLayout },
            set: { $0.chargeLayout = $1 }
        )
    }

    var editorSymbolColorIndex: Binding<Int> {
        editorCrestBinding(
            get: { $0.symbolColorIndex },
            set: { $0.symbolColorIndex = $1 }
        )
    }

    var editorTrimColorIndex: Binding<Int> {
        editorCrestBinding(
            get: { $0.trimColorIndex },
            set: { $0.trimColorIndex = $1 }
        )
    }

    private func editorCrestBinding<Field: Sendable>(
        get: @escaping @Sendable (BrowserSpaceCrest) -> Field,
        set: @escaping @Sendable (inout BrowserSpaceCrest, Field) -> Void
    ) -> Binding<Field> {
        Binding<Field>(
            get: { get(wrappedValue.crest) },
            set: { newValue in
                editorUpdateCrest { set(&$0, newValue) }
            }
        )
    }
}
