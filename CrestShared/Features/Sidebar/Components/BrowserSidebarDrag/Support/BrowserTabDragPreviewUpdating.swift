@MainActor
protocol BrowserTabDragPreviewUpdating: AnyObject {
    func updatePreview(for placement: TabPlacement)
    func dragStateDidEnd()
}
