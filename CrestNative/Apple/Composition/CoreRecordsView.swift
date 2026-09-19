import SwiftUI

struct CoreRecordsView: View {
    @Bindable var model: ControlPlaneModel
    @Bindable var pane: CoreNativePaneState
    @State private var query = ""
    @State private var offset = 0
    @State private var deleting: CoreRecord?
    @State private var confirmingClear = false
    private var isHistory: Bool { pane.kind == "history" }
    private var page: CoreRecordsPage? { model.recordsByTabID[pane.tabID] }
    private var queryIdentity: String { "\(pane.windowID)|\(pane.kind)|\(query)|\(offset)|\(model.recordsRevision)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isHistory ? "History" : "Archive").font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Clear all", role: .destructive) { confirmingClear = true }
                    .disabled(page?.total == 0 || page == nil)
            }
            TextField(isHistory ? "Search history" : "Search archive", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { offset = 0 }
            if let page {
                if page.items.isEmpty {
                    ContentUnavailableView(isHistory ? "No history" : "No archived tabs",
                        systemImage: isHistory ? "clock" : "archivebox")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(page.items) { record in
                        Button {
                            model.command(isHistory ? "core.open_history_entry" : "core.restore_tab", windowID: pane.windowID,
                                extra: ["spaceId": pane.spaceID, isHistory ? "entryId" : "tabId": record.id])
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title).lineLimit(1)
                                if let url = record.url { Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Text(Date(timeIntervalSince1970: record.date), format: .dateTime.month().day().hour().minute())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete", role: .destructive) { deleting = record } }
                    }
                }
                HStack {
                    Button("Previous") { offset = max(0, offset - 50) }.disabled(offset == 0)
                    Spacer()
                    Text(page.total == 1 ? "1 record" : "\(page.total) records").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Next") { offset += page.items.count }
                        .disabled(page.items.isEmpty || offset + page.items.count >= page.total)
                }
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .padding()
        .task(id: queryIdentity) {
            model.queryRecords(tabID: pane.tabID, windowID: pane.windowID, spaceID: pane.spaceID,
                kind: pane.kind, query: query, offset: offset)
        }
        .onDisappear { model.cancelRecords(tabID: pane.tabID) }
        .confirmationDialog("Delete this record?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                guard let deleting else { return }
                model.command(isHistory ? "core.delete_history_entry" : "core.delete_archived_tab", windowID: pane.windowID,
                    extra: ["spaceId": pane.spaceID, "entryId": deleting.id])
                self.deleting = nil
            }
        } message: { Text("This removes the record from this browsing session.") }
        .confirmationDialog(isHistory ? "Clear this Space’s history?" : "Clear this Space’s archive?", isPresented: $confirmingClear) {
            Button("Clear all", role: .destructive) {
                model.command(isHistory ? "core.clear_history" : "core.clear_archive", windowID: pane.windowID,
                    extra: ["spaceId": pane.spaceID])
                offset = 0
            }
        } message: { Text("This action cannot be undone.") }
    }
}
