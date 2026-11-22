import SwiftUI

/// A title that becomes a plain text editor in place. The binding is live;
/// finishing editing only dismisses focus and never gates saving the name.
struct BrowserInlineSpaceName: View {
    // MARK: - Static Variables

    /// The pencil's target where a finger may press it, and where only a
    /// pointer aims at it beside a small name or a large one.
    static let touchPencilSize = CGSize(width: 44, height: 44)
    static let smallPencilSize = CGSize(width: 24, height: 32)
    static let largePencilSize = CGSize(width: 32, height: 32)

    // MARK: - Variables

    @Binding var name: String
    var size: CGFloat = 30
    var titleFont: Font? = nil
    /// Set to put the name into editing; the view clears it once it has.
    var requestsEditing: Binding<Bool> = .constant(false)
    @State private var draftName = ""
    @State private var isEditing = false
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    @Environment(\.browserInteractionCapabilities) private var capabilities

    /// Whether a finger may press the name, which keeps its pencil showing
    /// rather than waiting for the pointer.
    private var usesTouch: Bool { capabilities.supportsTouch }

    private var pencilSize: CGSize {
        if usesTouch { return Self.touchPencilSize }
        return size <= 18 ? Self.smallPencilSize : Self.largePencilSize
    }

    // MARK: - Actions - Drawing

    var body: some View {
        HStack(spacing: size <= 18 ? 6 : 10) {
            #if os(iOS)
                if isEditing {
                    TextField("Space name", text: $draftName)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onAppear { isFocused = true }
                        .onChange(of: draftName) { _, value in name = value }
                        .onSubmit(finish)
                        .submitLabel(.done)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .accessibilityIdentifier("space-name-field")
                } else {
                    Button(action: edit) {
                        Text(name.isEmpty ? String(localized: "Name your Space") : name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Space name: \(name)")
                }
            #else
                if isEditing {
                    Text(draftName.isEmpty ? " " : draftName)
                        .lineLimit(1)
                        .padding(.trailing, 8)
                        .hidden()
                        .overlay(alignment: .leading) {
                            TextField("Space name", text: $draftName)
                                .textFieldStyle(.plain)
                                .focused($isFocused)
                                .onAppear { isFocused = true }
                                .onChange(of: draftName) { _, value in name = value }
                                .onSubmit(finish)
                                .submitLabel(.done)
                                .accessibilityIdentifier("space-name-field")
                        }
                } else {
                    Button {
                        edit()
                    } label: {
                        Text(name.isEmpty ? String(localized: "Name your Space") : name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Space name: \(name)")
                }
            #endif
            // While the name is being edited it's an ordinary field: Return,
            // Done or a click elsewhere finishes, and the pencil's place stays
            // so nothing moves.
            Button(action: edit) {
                Image(systemName: "pencil")
                    .font(.system(size: size <= 18 ? 14 : 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(!isEditing && (usesTouch || isHovering) ? 1 : 0)
            }
            .buttonStyle(CrestChromeButtonStyle(controlSize: pencilSize))
            .disabled(isEditing)
            .accessibilityHidden(isEditing)
            .accessibilityLabel("Edit Space name")
        }
        .font(titleFont ?? CrestTypography.display(size))
        .frame(minHeight: size <= 18 ? 32 : 44)
        .padding(.horizontal, size <= 18 ? 4 : 10)
        .padding(.vertical, 4)
        .background {
            // A field while the name is edited, with its focus ring, and the
            // design system's hover surface under the pointer otherwise.
            if isEditing {
                Color.clear.crestFieldSurface(isFocused: isFocused, minHeight: 0)
            } else {
                Color.clear.crestInteractiveSurface(
                    isSelected: false, isHovering: isHovering, cornerRadius: CrestFieldMetrics.cornerRadius)
            }
        }
        .onHover { isHovering = $0 }
        .onChange(of: isFocused) { _, focused in if !focused { isEditing = false } }
        .onChange(of: requestsEditing.wrappedValue, initial: true) { _, requested in
            guard requested else { return }
            requestsEditing.wrappedValue = false
            edit()
        }
        .background { PlatformInlineSpaceNameDismissal(isEditing: isEditing, finish: finish) }
        .padding(.leading, size <= 18 ? -4 : -10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions - Editing

    private func edit() {
        draftName = name
        isEditing = true
        isFocused = true
    }

    private func finish() {
        isFocused = false
        isEditing = false
    }
}

#if DEBUG
    #Preview("Rename a Space") {
        @Previewable @State var name = "Work"
        BrowserInlineSpaceName(name: $name).padding().frame(width: 360)
    }
#endif
