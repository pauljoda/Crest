import SwiftUI

struct BrowserSystemSymbolPicker: View {
    @Binding var selection: String
    @State private var isPresented = false

    var body: some View {
        BrowserArtworkPickerButton(
            title: "SF Symbol", detail: selection.isEmpty ? Text("Browse symbols") : Text(verbatim: selection)
        ) {
            isPresented = true
        } artwork: {
            Image(systemName: selection.isEmpty ? "square.grid.2x2" : selection)
        }
        .accessibilityLabel("Choose SF Symbol")
        .accessibilityValue(selection)
        .help(selection.isEmpty ? "Choose an SF Symbol" : selection)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            BrowserSystemSymbolCatalogPicker(selection: $selection)
                .presentationCompactAdaptation(.sheet)
        }
    }
}

private struct BrowserSystemSymbolCatalogPicker: View {
    @Binding var selection: String
    @State private var query = ""
    @State private var names: [String] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    private var matches: [String] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "." })
        return words.isEmpty ? names : names.filter { name in words.allSatisfy { name.contains($0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SF Symbols").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search symbols", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(matches, id: \.self) { name in
                        Button {
                            selection = name
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: name).font(.system(size: 26)).frame(height: 36)
                                Text(name.replacingOccurrences(of: ".", with: " "))
                                    .font(.caption2).lineLimit(2).frame(height: 30)
                            }
                            .frame(maxWidth: .infinity).padding(8)
                            .background(
                                selection == name ? Color.accentColor.opacity(0.12) : .primary.opacity(0.035),
                                in: .rect(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10).strokeBorder(
                                    selection == name ? Color.accentColor : .clear, lineWidth: 2)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain).help(name)
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(selection == name ? .isSelected : [])
                    }
                }
                .padding(2)
            }
            .overlay {
                if isLoading {
                    ProgressView("Loading symbols…")
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            Text("\(matches.count) symbols").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(idealWidth: 480, maxWidth: 520, idealHeight: 500, maxHeight: 600)
        .task {
            searchFocused = true
            names = await BrowserSystemSymbolCatalog.availableNames()
            isLoading = false
        }
    }
}

/// The name catalog is generated from a versioned export, never discovered via
/// private OS bundles. Artwork and availability come from public platform APIs.
@MainActor
private enum BrowserSystemSymbolCatalog {
    private static var loading: Task<[String], Never>?

    static func availableNames() async -> [String] {
        if let loading { return await loading.value }
        let task = Task { @MainActor in
            guard let url = Bundle.main.url(forResource: "SFSymbolNames", withExtension: "txt"),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { return [String]() }
            let candidates = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("//") }
            var available: [String] = []
            for (index, name) in candidates.enumerated() {
                let exists: Bool
                #if os(macOS)
                    exists = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
                #else
                    exists = UIImage(systemName: name) != nil
                #endif
                if exists { available.append(name) }
                if index.isMultiple(of: 100) { await Task.yield() }
            }
            return Array(Set(available)).sorted()
        }
        loading = task
        return await task.value
    }
}
