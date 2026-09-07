import SwiftUI

#if os(macOS)
    import AppKit
#endif

#if os(iOS)
    /// A native color picker with a full swatch-sized touch target and live updates.
    private struct BrowserSpacePaletteColorWell: View {
        @Binding var selection: Color
        @State private var isPresented = false

        var body: some View {
            Button {
                isPresented = true
            } label: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(selection)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.18)))
                    .overlay {
                        Image(systemName: "eyedropper")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.25), in: .circle)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isPresented) {
                NativePalettePicker(selection: $selection)
                    .overlay(alignment: .topTrailing) {
                        Button("Done") { isPresented = false }
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                    }
            }
        }
    }

    private struct NativePalettePicker: UIViewControllerRepresentable {
        @Binding var selection: Color
        func makeUIViewController(context: Context) -> UIColorPickerViewController {
            let picker = UIColorPickerViewController()
            picker.supportsAlpha = false
            picker.selectedColor = UIColor(selection)
            picker.delegate = context.coordinator
            return picker
        }
        func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
            context.coordinator.selection = $selection
            let color = UIColor(selection)
            if picker.selectedColor != color { picker.selectedColor = color }
        }
        func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
        final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
            var selection: Binding<Color>
            init(selection: Binding<Color>) { self.selection = selection }
            func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
                selection.wrappedValue = Color(uiColor: viewController.selectedColor)
            }
        }
    }
#endif

struct BrowserSpacePaletteSlot: View {
    let role: BrowserSpaceBrandColorRole
    let color: Binding<Color>?
    let canAdd: Bool
    let canRemove: Bool
    let compact: Bool
    let addColor: () -> Void
    let removeColor: () -> Void

    private var usesTouch: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let color {
                    BrowserSpacePaletteColorWell(selection: color)
                        .accessibilityLabel(Text(role.title))
                        .accessibilityIdentifier(
                            "space-branding-\(role.accessibilityIdentifierComponent)-color-picker")
                } else {
                    Button(action: addColor) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.primary.opacity(0.035), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        .secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            }
                            .contentShape(.rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : CrestOpacity.disabled)
                    .accessibilityLabel(Text(role.addColorTitle))
                    .accessibilityIdentifier("space-branding-add-\(role.accessibilityIdentifierComponent)-color")
                }
            }
            .frame(height: compact ? 56 : 64)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if canRemove {
                    Button(action: removeColor) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.red, in: .circle)
                            .overlay(Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .frame(width: usesTouch ? 44 : 22, height: usesTouch ? 44 : 22)
                    .contentShape(.rect)
                    .offset(x: usesTouch ? 11 : 5, y: usesTouch ? -11 : -5)
                    .accessibilityLabel(Text(role.removeColorTitle))
                    .accessibilityIdentifier("space-branding-remove-\(role.accessibilityIdentifierComponent)-color")
                }
            }
            Text(role.title)
                .font(CrestTypography.metadata)
                .lineLimit(1)
                .minimumScaleFactor(BrowserSpaceForgeMetrics.paletteLabelMinimumScale)
        }
        .frame(maxWidth: .infinity)
    }
}

#if os(macOS)
    /// A full-size native color well keeps the system picker, keyboard support,
    /// and color drag/drop while allowing the swatch to fill its palette column.
    private struct BrowserSpacePaletteColorWell: NSViewRepresentable {
        @Binding var selection: Color

        func makeNSView(context: Context) -> NSColorWell {
            let well = NSColorWell()
            well.colorWellStyle = .minimal
            well.supportsAlpha = false
            well.target = context.coordinator
            well.action = #selector(Coordinator.changeColor(_:))
            return well
        }

        func updateNSView(_ well: NSColorWell, context: Context) {
            context.coordinator.selection = $selection
            let color = NSColor(selection)
            if well.color != color { well.color = color }
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSColorWell, context: Context) -> CGSize? {
            CGSize(width: proposal.width ?? 100, height: proposal.height ?? 56)
        }

        func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

        static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
            well.deactivate()
        }

        final class Coordinator: NSObject {
            var selection: Binding<Color>
            init(selection: Binding<Color>) { self.selection = selection }
            @objc func changeColor(_ sender: NSColorWell) {
                selection.wrappedValue = Color(nsColor: sender.color)
            }
        }
    }
#endif
