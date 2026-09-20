#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
// In-process, main-thread native port. Objects and blocks never enter .NET.
@protocol CrestChromiumEngineHost <NSObject>
- (void)setBrowserObserver:(void (^)(NSDictionary<NSString *, id> *values))observer;
- (BOOL)createPage:(NSString *)pageID profile:(NSString *)profileID window:(NSString *)windowID
      privateMode:(BOOL)privateMode sourceProfile:(nullable NSString *)sourceProfileID
         observer:(void (^)(NSString *event, NSDictionary<NSString *, id> *values))observer;
- (BOOL)adoptPage:(NSString *)adoptionID asPage:(NSString *)pageID profile:(NSString *)profileID
         observer:(void (^)(NSString *event, NSDictionary<NSString *, id> *values))observer;
- (void)rejectAdoption:(NSString *)adoptionID;
- (nullable NSView *)viewForPage:(NSString *)pageID;
- (BOOL)preparePage:(NSString *)pageID forWindow:(NSString *)windowID;
- (void)didAttachPage:(NSString *)pageID window:(NSString *)windowID;
- (void)didDetachPage:(NSString *)pageID;
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
- (void)prepareToQuit:(void (^)(BOOL allowed))completion NS_SWIFT_NAME(prepareToQuit(_:));
- (void)cancelQuitPreparation;
@end
NS_ASSUME_NONNULL_END
