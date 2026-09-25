#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^CrestDeferredNavigation)(void);
// Which extension side-panel card change the engine asked the core for. A
// panel is a Crest page card, so the engine never opens or closes one itself.
typedef NS_ENUM(NSInteger, CrestSidePanelRequest) {
    CrestSidePanelRequestOpen,
    CrestSidePanelRequestClose,
    CrestSidePanelRequestToggle,
};
// In-process, main-thread native port. Objects and blocks never enter .NET.
@protocol CrestChromiumEngineHost <NSObject>
- (void)setBrowserObserver:(void (^)(NSDictionary<NSString *, id> *values))observer;
- (void)setDownloadObserver:(void (^)(NSDictionary<NSString *, id> *values))observer;
- (void)setDownloadDestinationResolver:(void (^)(NSDictionary<NSString *, id> *values, void (^reply)(NSString * _Nullable path)))resolver;
- (void)cancelDownload:(NSString *)downloadID profile:(NSString *)profileID;
- (void)removeDownload:(NSString *)downloadID profile:(NSString *)profileID;
- (void)approveDownload:(NSString *)downloadID profile:(NSString *)profileID warning:(NSString *)token;
- (void)deleteProfile:(NSString *)profileID ephemeral:(BOOL)ephemeral completion:(void (^)(BOOL deleted))completion;
// The engine binding creates, loads and closes the pages the core opens, and
// reports what they do straight to the core. The platform observes each one's
// presentation, which may begin before the binding has created it.
// TRANSITIONAL until page presentation travels as EnginePresentations.
- (void)observePage:(NSString *)pageID
           observer:(void (^)(NSString *event, NSDictionary<NSString *, id> *values))observer;
// A Settings page of the engine's own, such as its flags page, which no tab
// owns and the core never hears of. TRANSITIONAL until such pages open through
// the core.
- (BOOL)createPage:(NSString *)pageID profile:(NSString *)profileID window:(NSString *)windowID
      privateMode:(BOOL)privateMode sourceProfile:(nullable NSString *)sourceProfileID
         observer:(void (^)(NSString *event, NSDictionary<NSString *, id> *values))observer;
// Makes a page the engine offered the page the core is opening, instead of a
// new one.
- (BOOL)adoptPage:(NSString *)adoptionID asPage:(NSString *)pageID
         observer:(void (^)(NSString *event, NSDictionary<NSString *, id> *values))observer;
- (void)rejectAdoption:(NSString *)adoptionID;
// What the platform asks of a page directly. TRANSITIONAL until the direct
// path's PageRequests: the app's own load, a link navigation staged for the
// page's first load, the icon the engine found for its document, and the
// regular profile a private window's pages derive from.
- (void)loadPage:(NSString *)pageID url:(NSString *)url;
- (BOOL)stageNavigation:(NSString *)token page:(NSString *)pageID url:(NSString *)url;
- (nullable NSData *)iconForPage:(NSString *)pageID;
- (void)setPrivateSourceProfile:(NSString *)profileID;
- (nullable NSView *)viewForPage:(NSString *)pageID;
- (void)setLinkHandlerForPage:(NSString *)pageID
                     handler:(BOOL (^)(NSString *action, NSString *url, NSString *label))handler
    NS_SWIFT_NAME(setLinkHandler(page:handler:));
- (void)setContextMenuHandlerForPage:(NSString *)pageID
    provider:(NSArray<NSDictionary<NSString *, NSString *> *> * (^)(NSString *url, NSString *selection))provider
    action:(BOOL (^)(NSString *identifier, NSString *url, NSString *selection))action
    NS_SWIFT_NAME(setContextMenuHandler(page:provider:action:));
- (void)setJavaScriptDialogHandlerForPage:(NSString *)pageID
    handler:(void (^)(NSString *kind, NSString *message, NSString *defaultText,
        NSString *sourceURL, void (^reply)(BOOL accepted, NSString * _Nullable input)))handler
    NS_SWIFT_NAME(setJavaScriptDialogHandler(page:handler:));
- (void)setHTTPAuthenticationHandlerForPage:(NSString *)pageID
    handler:(void (^)(NSDictionary<NSString *, id> *challenge,
        void (^reply)(NSString * _Nullable username, NSString * _Nullable password)))handler
    NS_SWIFT_NAME(setHTTPAuthenticationHandler(page:handler:));
- (void)setProtectedLinkHandlerForPage:(NSString *)pageID
    handler:(CrestDeferredNavigation _Nullable (^)(NSString *url))handler
    NS_SWIFT_NAME(setProtectedLinkHandler(page:handler:));
- (void)setModifiedLinkHandlerForPage:(NSString *)pageID
    handler:(void (^)(NSString *url, NSUInteger modifiers, NSString *token,
        void (^reply)(NSString *decision, CrestDeferredNavigation _Nullable present)))handler
    NS_SWIFT_NAME(setModifiedLinkHandler(page:handler:));
- (void)discardPendingNavigation:(NSString *)token;
- (nullable NSData *)interactionStateForPage:(NSString *)pageID;
- (BOOL)restorePage:(NSString *)pageID interactionState:(NSData *)state expectedURL:(NSString *)url;
- (BOOL)preparePage:(NSString *)pageID forWindow:(NSString *)windowID;
- (void)didAttachPage:(NSString *)pageID window:(NSString *)windowID;
- (void)didDetachPage:(NSString *)pageID;
- (nullable NSDictionary<NSString *, id> *)mediaActivityForPage:(NSString *)pageID;
- (void)capturePage:(NSString *)pageID rect:(NSRect)rect width:(CGFloat)width
         completion:(void (^)(NSImage * _Nullable image))completion;
- (void)exportPage:(NSString *)pageID format:(NSString *)format width:(CGFloat)width
        completion:(void (^)(NSData * _Nullable data, NSString * _Nullable error))completion;
- (BOOL)command:(NSString *)command page:(NSString *)pageID url:(nullable NSString *)url;
// The DER certificate chain of the page's visible entry, leaf first; empty
// when the page was not loaded over a verified TLS connection.
// Site permission requests the page's Crest record covers — camera,
// microphone, location, notifications. The handler replies 1 allow, 2 allow
// this time, 3 block, 4 dismiss; other requests keep the engine's own prompt.
- (void)setPermissionHandlerForPage:(NSString *)pageID
                            handler:(void (^)(NSDictionary<NSString *, id> *request, void (^reply)(NSInteger response)))handler
    NS_SWIFT_NAME(setPermissionHandler(page:handler:));
- (NSArray<NSData *> *)certificateChainForPage:(NSString *)pageID;
// Removes the page's site cookies, storage and cache from its profile.
- (void)clearSiteDataForPage:(NSString *)pageID completion:(void (^)(BOOL cleared))completion
    NS_SWIFT_NAME(clearSiteData(page:completion:));
- (NSArray<NSDictionary<NSString *, id> *> *)permissionsForPage:(NSString *)pageID;
- (BOOL)setPermission:(NSString *)permissionID page:(NSString *)pageID value:(NSInteger)value;
- (NSArray<NSDictionary<NSString *, id> *> *)extensionsForPage:(NSString *)pageID;
- (BOOL)runExtension:(NSString *)extensionID page:(NSString *)pageID
         anchorView:(NSView *)anchorView anchorRect:(NSRect)anchorRect;
// The pinned extension actions of a Space, independent of any page. A Space
// showing its Start Page still has the extensions the user pinned to it, so the
// toolbar row is driven from the Space's own profile and the per-page list is
// overlaid on it when a page exists. A private window passes the profile its
// pages were opened with and is narrowed to incognito-enabled extensions.
// Entries carry `enabled: NO` when the action needs a page and there is none.
- (NSArray<NSDictionary<NSString *, id> *> *)pinnedExtensionsForProfile:(NSString *)profileID
    NS_SWIFT_NAME(pinnedExtensions(profile:));
// Runs a pinned action with no page open. Only an action carrying its own
// popup document can run: there is no tab to activate, grant host access for or
// inject into. Returns NO for anything else, including a page action.
- (BOOL)runExtension:(NSString *)extensionID profile:(NSString *)profileID window:(NSString *)windowID
          anchorView:(NSView *)anchorView anchorRect:(NSRect)anchorRect
    NS_SWIFT_NAME(runExtension(_:profile:window:anchorView:anchorRect:));
// Extension side panels. A panel is hosted as a Crest split-row card beside
// the page it belongs to: it is not a tab, is never persisted and never syncs.
// `closed` runs when the panel document or its extension host goes away.
- (BOOL)hasSidePanel:(NSString *)extensionID page:(NSString *)pageID
    NS_SWIFT_NAME(hasSidePanel(_:page:));
- (nullable NSView *)openSidePanel:(NSString *)extensionID page:(NSString *)pageID
                            closed:(void (^)(void))closed
    NS_SWIFT_NAME(openSidePanel(_:page:closed:));
- (void)closeSidePanelForPage:(NSString *)pageID NS_SWIFT_NAME(closeSidePanel(page:));
// Docked DevTools. A Crest window is the user's window, so a docked inspector
// is mounted inside the page card it inspects instead of opening a window of
// its own. The engine offers and withdraws the frontend through
// `CrestRoot.routeDevTools(page:)`; this reads back what it offered.
//
// `devToolsViewForPage:` is the frontend's container while an inspector is
// docked on that page, and nil otherwise. `layoutDevToolsForPage:container:`
// resolves where the frontend and the inspected page go inside `container`,
// which is the whole card interior, and returns AppKit rectangles under the
// `devTools` and `page` keys — the frontend's own dock side and size are
// encoded in the resizing strategy the engine keeps for that page. A `page`
// rectangle with no area means the frontend is covering the page on purpose.
- (nullable NSView *)devToolsViewForPage:(NSString *)pageID NS_SWIFT_NAME(devToolsView(page:));
- (nullable NSDictionary<NSString *, NSValue *> *)layoutDevToolsForPage:(NSString *)pageID
    container:(NSRect)container NS_SWIFT_NAME(layoutDevTools(page:container:));
// chrome.commands. The shortcut's target in the active page's own profile, or
// nil when no enabled extension bound it. A named command has already been
// delivered to its extension and reports `handled`; an `_execute_action`
// binding reports the `action` whose extension the core runs itself, so the
// popup keeps the core's own anchor.
- (nullable NSDictionary<NSString *, id> *)dispatchExtensionShortcut:(NSEvent *)event
    page:(NSString *)pageID NS_SWIFT_NAME(dispatchExtensionShortcut(_:page:));
- (void)prepareExtensionProfile:(NSString *)profileID completion:(void (^)(BOOL ready))completion;
- (NSArray<NSDictionary<NSString *, id> *> *)extensionsForProfile:(NSString *)profileID;
- (BOOL)extensionCommand:(NSString *)command extension:(NSString *)extensionID profile:(NSString *)profileID window:(NSString *)windowID;
- (void)setExtensionReview:(void (^)(NSDictionary<NSString *, id> *values, NSWindow *window, void (^reply)(BOOL accept, BOOL withhold)))review;
- (NSString *)engineVersion;
- (BOOL)installExtension:(NSString *)extensionID package:(NSString *)path profile:(NSString *)profileID window:(NSString *)windowID
              completion:(void (^)(BOOL installed, NSString *message))completion;
// Finds the next match, always wrapping at the end of the page. The completion
// receives the total number of matches and the 1-based ordinal of the selected
// one; zero matches means nothing was found.
- (BOOL)findInPage:(NSString *)pageID query:(NSString *)query backwards:(BOOL)backwards
     caseSensitive:(BOOL)caseSensitive
        completion:(void (^)(NSInteger matches, NSInteger activeMatch))completion;
- (void)disposePages;
- (void)disposePages:(NSArray<NSString *> *)pageIDs windows:(NSArray<NSString *> *)windowIDs
    releaseProfiles:(NSArray<NSString *> *)profileIDs;
- (void)completeQuit;
- (void)prepareToClosePages:(NSArray<NSString *> *)pageIDs windows:(NSArray<NSString *> *)windowIDs
                completion:(void (^)(BOOL allowed))completion NS_SWIFT_NAME(prepareToClose(pages:windows:completion:));
- (void)prepareToQuit:(void (^)(BOOL allowed))completion NS_SWIFT_NAME(prepareToQuit(_:));
- (void)cancelQuitPreparation;
// Content bridges. A source runs in Crest's own isolated world of every
// document the page loads, or of its main frame only; its `postMessage`
// calls arrive as `content_message` observations naming the frame. An
// evaluation runs in that frame's current document only and answers the JSON
// of its result, or nil when the document is gone.
- (BOOL)addContentScript:(NSString *)source page:(NSString *)pageID mainFrameOnly:(BOOL)mainFrameOnly;
- (void)evaluateContentScript:(NSString *)source page:(NSString *)pageID frame:(NSString *)frameID
                   completion:(void (^)(NSString * _Nullable json))completion;
// Declines a system sign-in the core could not place, so the requesting app
// learns at once rather than waiting on a window that will never open.
- (void)cancelAuthenticationSessionForWindow:(NSString *)windowID NS_SWIFT_NAME(cancelAuthenticationSession(window:));
@end
NS_ASSUME_NONNULL_END
