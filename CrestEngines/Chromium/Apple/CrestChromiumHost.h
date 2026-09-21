#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^CrestDeferredNavigation)(void);
// In-process, main-thread native port. Objects and blocks never enter .NET.
@protocol CrestChromiumEngineHost <NSObject>
- (void)setBrowserObserver:(void (^)(NSDictionary<NSString *, id> *values))observer;
- (void)setDownloadObserver:(void (^)(NSDictionary<NSString *, id> *values))observer;
- (void)setDownloadDestinationResolver:(void (^)(NSDictionary<NSString *, id> *values, void (^reply)(NSString * _Nullable path)))resolver;
- (void)cancelDownload:(NSString *)downloadID profile:(NSString *)profileID;
- (void)removeDownload:(NSString *)downloadID profile:(NSString *)profileID;
- (void)approveDownload:(NSString *)downloadID profile:(NSString *)profileID warning:(NSString *)token;
- (void)deleteProfile:(NSString *)profileID ephemeral:(BOOL)ephemeral completion:(void (^)(BOOL deleted))completion;
- (BOOL)createPage:(NSString *)pageID profile:(NSString *)profileID window:(NSString *)windowID
      privateMode:(BOOL)privateMode sourceProfile:(nullable NSString *)sourceProfileID
         observer:(void (^)(NSString *event, NSDictionary<NSString *, id> *values))observer;
- (BOOL)adoptPage:(NSString *)adoptionID asPage:(NSString *)pageID profile:(NSString *)profileID
         observer:(void (^)(NSString *event, NSDictionary<NSString *, id> *values))observer;
- (void)rejectAdoption:(NSString *)adoptionID;
- (nullable NSView *)viewForPage:(NSString *)pageID;
- (void)setLinkHandlerForPage:(NSString *)pageID
                     handler:(BOOL (^)(NSString *action, NSString *url, NSString *label))handler
    NS_SWIFT_NAME(setLinkHandler(page:handler:));
- (void)setProtectedLinkHandlerForPage:(NSString *)pageID
    handler:(CrestDeferredNavigation _Nullable (^)(NSString *url))handler
    NS_SWIFT_NAME(setProtectedLinkHandler(page:handler:));
- (void)setModifiedLinkHandlerForPage:(NSString *)pageID
    handler:(void (^)(NSString *url, NSUInteger modifiers, NSString *token,
        void (^reply)(NSString *decision, CrestDeferredNavigation _Nullable present)))handler
    NS_SWIFT_NAME(setModifiedLinkHandler(page:handler:));
- (BOOL)loadPendingNavigation:(NSString *)token page:(NSString *)pageID expectedURL:(NSString *)url;
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
- (NSArray<NSDictionary<NSString *, id> *> *)permissionsForPage:(NSString *)pageID;
- (BOOL)setPermission:(NSString *)permissionID page:(NSString *)pageID value:(NSInteger)value;
- (NSArray<NSDictionary<NSString *, id> *> *)extensionsForPage:(NSString *)pageID;
- (BOOL)runExtension:(NSString *)extensionID page:(NSString *)pageID
         anchorView:(NSView *)anchorView anchorRect:(NSRect)anchorRect;
- (void)prepareExtensionProfile:(NSString *)profileID completion:(void (^)(BOOL ready))completion;
- (NSArray<NSDictionary<NSString *, id> *> *)extensionsForProfile:(NSString *)profileID;
- (BOOL)extensionCommand:(NSString *)command extension:(NSString *)extensionID profile:(NSString *)profileID window:(NSString *)windowID;
- (void)setExtensionReview:(void (^)(NSDictionary<NSString *, id> *values, NSWindow *window, void (^reply)(BOOL accept, BOOL withhold)))review;
- (NSString *)engineVersion;
- (BOOL)installExtension:(NSString *)extensionID package:(NSString *)path profile:(NSString *)profileID window:(NSString *)windowID
              completion:(void (^)(BOOL installed, NSString *message))completion;
- (BOOL)findInPage:(NSString *)pageID query:(NSString *)query backwards:(BOOL)backwards
     caseSensitive:(BOOL)caseSensitive completion:(void (^)(BOOL found))completion;
- (void)disposePages;
- (void)disposePages:(NSArray<NSString *> *)pageIDs windows:(NSArray<NSString *> *)windowIDs
    releaseProfiles:(NSArray<NSString *> *)profileIDs;
- (void)completeQuit;
- (void)prepareToClosePages:(NSArray<NSString *> *)pageIDs windows:(NSArray<NSString *> *)windowIDs
                completion:(void (^)(BOOL allowed))completion NS_SWIFT_NAME(prepareToClose(pages:windows:completion:));
- (void)prepareToQuit:(void (^)(BOOL allowed))completion NS_SWIFT_NAME(prepareToQuit(_:));
- (void)cancelQuitPreparation;
@end
NS_ASSUME_NONNULL_END
