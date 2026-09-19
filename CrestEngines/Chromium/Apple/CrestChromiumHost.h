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
- (void)disposePages;
- (void)disposePages:(NSArray<NSString *> *)pageIDs windows:(NSArray<NSString *> *)windowIDs
    releaseProfiles:(NSArray<NSString *> *)profileIDs;
- (void)completeQuit;
- (void)prepareToQuit:(void (^)(BOOL allowed))completion NS_SWIFT_NAME(prepareToQuit(_:));
- (void)cancelQuitPreparation;
@end
NS_ASSUME_NONNULL_END
