import AppKit
import Darwin
import ObjectiveC.runtime

/// Receives the live AppKit view from the same presentation entry point
/// both engines already use. The hooks affect Crest's process only.
@MainActor
final class BrowserPictureInPicturePresenter {
    // MARK: - Types

    private enum PresentationEngine {
        case webKit
        case chromium
    }

    private struct Presentation {
        let engine: PresentationEngine
        let presenter: NSViewController
        let source: NSViewController
        let window: BrowserPictureInPictureWindow
    }

    // MARK: - Static Variables

    private static let shared = BrowserPictureInPicturePresenter()
    static let installed = shared.install()

    // MARK: - Variables

    private let managed = NSHashTable<NSViewController>.weakObjects()
    private let playback = NSMapTable<NSViewController, NSNumber>.weakToStrongObjects()
    private var active: Presentation?
    private weak var sourcePage: BrowserPage?
    private var findSourcePage: (NSView) -> BrowserPage? = { _ in nil }
    private var openSettings: (BrowserPage?, NSWindow?) -> Void = { _, _ in }
    private var restingFrame: NSRect?

    private var delegateSelector: Selector { NSSelectorFromString("delegate") }

    // MARK: - Actions - App

    static func configure(
        findSourcePage: @escaping (NSView) -> BrowserPage?,
        openSettings: @escaping (BrowserPage?, NSWindow?) -> Void
    ) {
        shared.findSourcePage = findSourcePage
        shared.openSettings = openSettings
    }

    static func webKitEntered(from page: BrowserPage) {
        guard shared.active?.engine == .webKit, shared.sourcePage == nil else { return }
        shared.bindSource(page)
    }

    static func refreshVideoSurface() {
        shared.active?.window.refreshVideoSurface()
    }

    // MARK: - Actions - Framework

    private func install() -> Bool {
        guard dlopen("/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP", RTLD_LAZY | RTLD_LOCAL) != nil,
            let type = NSClassFromString("PIPViewController")
        else { return false }
        let present = NSSelectorFromString("presentViewControllerAsPictureInPicture:")
        let dismiss = NSSelectorFromString("dismissViewController:")
        let setPlaying = NSSelectorFromString("setPlaying:")
        let setAspect = NSSelectorFromString("setAspectRatio:")
        guard let entry = class_getInstanceMethod(type, present),
            let exit = class_getInstanceMethod(type, dismiss),
            let playing = class_getInstanceMethod(type, setPlaying),
            let aspect = class_getInstanceMethod(type, setAspect),
            class_getInstanceMethod(type, NSSelectorFromString("aspectRatio")) != nil,
            class_getInstanceMethod(type, delegateSelector) != nil
        else { return false }

        typealias PresentationCall = @convention(c) (NSViewController, Selector, NSViewController) -> Void
        let originalEntry = unsafeBitCast(method_getImplementation(entry), to: PresentationCall.self)
        let originalExit = unsafeBitCast(method_getImplementation(exit), to: PresentationCall.self)
        replace(
            type, present, entry,
            { [self] presenter, source in
                guard Thread.isMainThread else {
                    originalEntry(presenter, present, source)
                    return
                }
                MainActor.assumeIsolated {
                    if let engine = presentationEngine(for: presenter) {
                        show(source, on: presenter, engine: engine)
                    } else {
                        originalEntry(presenter, present, source)
                    }
                }
            } as @convention(block) (NSViewController, NSViewController) -> Void)
        replace(
            type, dismiss, exit,
            { [self] presenter, source in
                guard Thread.isMainThread else {
                    originalExit(presenter, dismiss, source)
                    return
                }
                MainActor.assumeIsolated {
                    if !dismissIfManaged(source, on: presenter) { originalExit(presenter, dismiss, source) }
                }
            } as @convention(block) (NSViewController, NSViewController) -> Void)

        typealias PlayingCall = @convention(c) (NSViewController, Selector, Bool) -> Void
        let originalPlaying = unsafeBitCast(method_getImplementation(playing), to: PlayingCall.self)
        replace(
            type, setPlaying, playing,
            { [self] presenter, isPlaying in
                originalPlaying(presenter, setPlaying, isPlaying)
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated { updatePlaying(isPlaying, on: presenter) }
            } as @convention(block) (NSViewController, Bool) -> Void)

        typealias AspectCall = @convention(c) (NSViewController, Selector, NSSize) -> Void
        let originalAspect = unsafeBitCast(method_getImplementation(aspect), to: AspectCall.self)
        replace(
            type, setAspect, aspect,
            { [self] presenter, ratio in
                originalAspect(presenter, setAspect, ratio)
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated {
                    if active?.presenter === presenter { active?.window.setVideoSize(ratio) }
                }
            } as @convention(block) (NSViewController, NSSize) -> Void)

        // Newer WebKit builds send a playback-state object in place of setPlaying.
        let setPlayback = NSSelectorFromString("_setPlaybackState:")
        if let method = class_getInstanceMethod(type, setPlayback) {
            typealias PlaybackCall = @convention(c) (NSViewController, Selector, NSObject?) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: PlaybackCall.self)
            replace(
                type, setPlayback, method,
                { [self] presenter, state in
                    original(presenter, setPlayback, state)
                    guard Thread.isMainThread, let state else { return }
                    MainActor.assumeIsolated {
                        let selector = NSSelectorFromString("timeControlStatus")
                        guard state.responds(to: selector) else { return }
                        typealias Status = @convention(c) (NSObject, Selector) -> Int
                        let read = unsafeBitCast(state.method(for: selector), to: Status.self)
                        updatePlaying(read(state, selector) != 0, on: presenter)
                    }
                } as @convention(block) (NSViewController, NSObject?) -> Void)
        }
        return true
    }

    private func replace(_ cls: AnyClass, _ selector: Selector, _ method: Method, _ block: Any) {
        // Replacing on this class also covers an inherited implementation
        // without modifying NSViewController itself.
        class_replaceMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    // MARK: - Actions - Presentation

    private func presentationEngine(for presenter: NSViewController) -> PresentationEngine? {
        guard let delegate = delegate(of: presenter) else { return nil }
        if let type = NSClassFromString("CrestPictureInPictureDelegate"), delegate.isKind(of: type) {
            return .chromium
        }
        // OS releases have used both names for WebKit's video presenter.
        let names = ["WebVideoPresentationInterfaceMacObjC", "WebVideoFullscreenInterfaceMacObjC"]
        return names.contains { name in
            NSClassFromString(name).map { delegate.isKind(of: $0) } == true
        } ? .webKit : nil
    }

    private func show(_ source: NSViewController, on presenter: NSViewController, engine: PresentationEngine) {
        if active?.presenter === presenter, active?.source === source { return }
        if let previous = active { stop(previous) }
        managed.add(presenter)
        let view = source.view
        let inlineWindow = view.window
        let inline = inlineWindow.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) }
        let aspectSelector = NSSelectorFromString("aspectRatio")
        typealias Aspect = @convention(c) (NSViewController, Selector) -> NSSize
        let aspect = unsafeBitCast(presenter.method(for: aspectSelector), to: Aspect.self)(presenter, aspectSelector)
        let window = BrowserPictureInPictureWindow(
            videoSize: aspect, restingFrame: restingFrame, sourceScreen: inlineWindow?.screen,
            isPlaying: playback.object(forKey: presenter)?.boolValue ?? false)
        let presentation = Presentation(engine: engine, presenter: presenter, source: source, window: window)
        active = presentation
        if engine == .chromium {
            let pageSelector = NSSelectorFromString("crestPictureInPicturePageView")
            if view.responds(to: pageSelector),
                let pageView = view.perform(pageSelector)?.takeUnretainedValue() as? NSView
            {
                bindSource(findSourcePage(pageView))
            }
        }

        window.onClose = { [weak self, weak window] in
            guard let self, let active, active.window === window else { return }
            stop(active)
        }
        window.onRestore = { [weak self, weak window] in
            guard let self, let active, active.window === window else { return }
            if shouldClose(active) { finish(active) }
        }
        window.onSettings = { [weak self, weak window, weak inlineWindow] in
            guard let self, let window, active?.window === window else { return }
            openSettings(sourcePage, inlineWindow)
        }
        window.onPlayback = { [weak self, weak window] playing in
            guard let self, let active, active.window === window else { return }
            call(playing ? "pipActionPlay:" : "pipActionPause:", on: active)
        }
        // WebKit checks the supplied container is below the presenter's view.
        presenter.view = window.videoContainer
        window.present(view, from: inline)
    }

    private func bindSource(_ page: BrowserPage?) {
        sourcePage = page
        let space = page.flatMap {
            $0.host?.browser.spaceModel(
                matching: BrowserSpaceRuntimeAssignment(spaceID: $0.spaceID, profileID: $0.profileID))
        }
        active?.window.setSourceSpace(space)
    }

    private func dismissIfManaged(_ source: NSViewController, on presenter: NSViewController) -> Bool {
        guard managed.contains(presenter) else { return false }
        if let active, active.presenter === presenter, active.source === source { finish(active) }
        return true
    }

    private func updatePlaying(_ isPlaying: Bool, on presenter: NSViewController) {
        playback.setObject(NSNumber(value: isPlaying), forKey: presenter)
        if active?.presenter === presenter { active?.window.isPlaying = isPlaying }
    }

    private func stop(_ presentation: Presentation) {
        call("pipActionStop:", on: presentation)
        if active?.window === presentation.window { finish(presentation) }
    }

    private func finish(_ presentation: Presentation) {
        active = nil
        sourcePage = nil
        restingFrame = presentation.window.restingFrame
        presentation.window.dismiss()
        // The engine transitions to exiting after its dismiss call returns.
        DispatchQueue.main.async { [self] in
            call("pipDidClose:", on: presentation)
        }
    }

    // MARK: - Actions - Engine callbacks

    private func delegate(of presenter: NSViewController) -> NSObject? {
        presenter.perform(delegateSelector)?.takeUnretainedValue() as? NSObject
    }

    private func call(_ name: String, on presentation: Presentation) {
        let selector = NSSelectorFromString(name)
        guard let delegate = delegate(of: presentation.presenter), delegate.responds(to: selector) else { return }
        typealias Callback = @convention(c) (NSObject, Selector, NSViewController) -> Void
        unsafeBitCast(delegate.method(for: selector), to: Callback.self)(delegate, selector, presentation.presenter)
    }

    private func shouldClose(_ presentation: Presentation) -> Bool {
        let selector = NSSelectorFromString("pipShouldClose:")
        guard let delegate = delegate(of: presentation.presenter), delegate.responds(to: selector) else { return true }
        typealias Callback = @convention(c) (NSObject, Selector, NSViewController) -> Bool
        return unsafeBitCast(delegate.method(for: selector), to: Callback.self)(
            delegate, selector, presentation.presenter)
    }
}
