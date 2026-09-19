#import <Cocoa/Cocoa.h>
#import "CrestChromiumHost.h"

#include <algorithm>
#include <map>
#include <memory>
#include <string>
#include <set>
#include "base/check.h"
#include "base/functional/bind.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_destroyer.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "base/command_line.h"
#include "base/no_destructor.h"
#include "base/uuid.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/base/page_transition_types.h"

@interface CrestRoot : NSObject
+ (void)startWithHost:(id<CrestChromiumEngineHost>)host;
+ (NSWindow*)windowForIdentifier:(NSString*)identifier;
+ (BOOL)deferQuit;
@end

namespace {
using Observation = void (^)(NSString*, NSDictionary<NSString*, id>*);
struct Page;
struct BrowserOwner;
struct NativeAdoption {
  base::WeakPtr<content::WebContents> contents;
  std::string profile;
};
struct HostState {
  Browser* bootstrap = nullptr;
  Profile* root_profile = nullptr;
  bool started = false;
  bool disposing = false;
  bool quitting = false;
  uint64_t quit_generation = 0;
  Browser* quit_browser = nullptr;
  void (^quit_preflight)(BOOL);
  std::string creating_window;
  std::map<std::string, Profile*> profiles;
  std::map<std::string, std::unique_ptr<ScopedProfileKeepAlive>> profile_leases;
  std::set<std::string> creating_pages;
  std::map<std::string, std::unique_ptr<BrowserOwner>> browsers;
  std::map<std::string, std::unique_ptr<Page>> pages;
  std::map<std::string, NativeAdoption> adoptions;
  void (^browser_observation)(NSDictionary<NSString*, id>*);
};
HostState& State() { static base::NoDestructor<HostState> state; return *state; }

struct Page final : content::WebContentsObserver {
  Page(content::WebContents* contents, Browser* owner, std::string profile_id,
       Observation observer)
      : content::WebContentsObserver(contents), browser(owner),
        profile(std::move(profile_id)), observation([observer copy]) {}
  Browser* browser;
  std::string profile;
  Observation observation;
  bool closing = false;
  void Publish(bool committed = false, NSString* failure = nil) {
    if (!web_contents() || State().disposing) return;
    auto& controller = web_contents()->GetController();
    observation(@"changed", @{
      @"url": base::SysUTF8ToNSString(web_contents()->GetVisibleURL().spec()),
      @"title": base::SysUTF16ToNSString(web_contents()->GetTitle()),
      @"isLoading": @(web_contents()->IsLoading()),
      @"canGoBack": @(controller.CanGoBack()), @"canGoForward": @(controller.CanGoForward()),
      @"committed": @(committed), @"failure": failure ?: (id)NSNull.null });
  }
  void DidStartLoading() override { Publish(); }
  void DidStopLoading() override { Publish(); }
  void TitleWasSet(content::NavigationEntry*) override { Publish(); }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame())
      Publish(navigation->HasCommitted() && !navigation->IsErrorPage(),
              navigation->IsErrorPage() ? @"navigation_failed" : nil);
  }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    Publish(false, @"process_terminated");
  }
  void BeforeUnloadDialogCancelled() override {
    if (!closing || State().disposing) return;
    closing = false;
    observation(@"close_canceled", @{});
  }
  void BeforeUnloadFired(bool proceed) override {
    if (!proceed) BeforeUnloadDialogCancelled();
  }
  void WebContentsDestroyed() override {
    Observe(nullptr);
    if (!State().disposing) observation(@"closed", @{});
  }
};

void OfferNativePage(base::WeakPtr<content::WebContents> contents, bool foreground);

struct BrowserOwner final : TabStripModelObserver {
  BrowserOwner(Browser* value, std::string native_window)
      : browser(value), window(std::move(native_window)), strip(value->tab_strip_model()) {
    strip->AddObserver(this);
  }
  ~BrowserOwner() override { if (strip) strip->RemoveObserver(this); }
  Browser* browser;
  std::string window;
  TabStripModel* strip;
  void OnTabStripModelChanged(TabStripModel*, const TabStripModelChange& change,
                             const TabStripSelectionChange& selection) override {
    if (change.type() != TabStripModelChange::kInserted || State().disposing) return;
    for (const auto& inserted : change.GetInsert()->contents) {
      auto weak = inserted.contents->GetWeakPtr();
      const bool foreground = selection.new_contents == inserted.contents;
      // Navigate() registers core-created pages before this next UI-thread turn.
      dispatch_async(dispatch_get_main_queue(), ^{ OfferNativePage(weak, foreground); });
    }
  }
  void OnTabCloseCancelled(const tabs::TabInterface* tab) override {
    for (auto& [id, page] : State().pages) {
      if (page->web_contents() == tab->GetContents() && page->closing) {
        page->closing = false;
        page->observation(@"close_canceled", @{});
        return;
      }
    }
  }
  void OnTabStripModelDestroyed(TabStripModel*) override { strip = nullptr; }
};

void OfferNativePage(base::WeakPtr<content::WebContents> contents, bool foreground) {
  auto& state = State();
  if (!contents || state.disposing || !state.browser_observation) return;
  for (const auto& [id, page] : state.pages) if (page->web_contents() == contents.get()) return;
  for (const auto& [id, adoption] : state.adoptions) if (adoption.contents.get() == contents.get()) return;
  std::string profile_id;
  for (const auto& [id, profile] : state.profiles)
    if (profile == contents->GetBrowserContext()) { profile_id = id; break; }
  if (profile_id.empty()) return;
  const std::string token = base::Uuid::GenerateRandomV4().AsLowercaseString();
  state.adoptions.emplace(token, NativeAdoption{contents, profile_id});
  id source_id = NSNull.null;
  if (auto* opener = contents->GetOpener()) {
    auto* source = content::WebContents::FromRenderFrameHost(opener);
    for (const auto& [id, page] : state.pages)
      if (page->web_contents() == source) { source_id = base::SysUTF8ToNSString(id); break; }
  }
  NSString* url = base::SysUTF8ToNSString(contents->GetVisibleURL().spec());
  id native_window = NSNull.null;
  for (const auto& [id, owner] : state.browsers)
    if (owner->strip && owner->strip->GetIndexOfWebContents(contents.get()) >= 0) {
      native_window = base::SysUTF8ToNSString(owner->window); break;
    }
  state.browser_observation(@{
    @"adoptionId": base::SysUTF8ToNSString(token), @"profileId": base::SysUTF8ToNSString(profile_id),
    @"windowId": native_window,
    @"sourcePageId": source_id, @"url": url.length ? url : @"about:blank", @"foreground": @(foreground) });
}

Browser* BrowserFor(const std::string& profile_id, const std::string& window_id) {
  auto& state = State();
  const std::string key = profile_id + "/" + window_id;
  if (auto found = state.browsers.find(key); found != state.browsers.end())
    return found->second->browser;
  auto found = state.profiles.find(profile_id);
  if (found == state.profiles.end()) return nullptr;
  Profile* profile = found->second;
  state.creating_window = window_id;
  Browser* browser = Browser::Create(Browser::CreateParams(profile, false));
  state.creating_window.clear();
  state.browsers.emplace(key, std::make_unique<BrowserOwner>(browser, window_id));
  return browser;
}
void ResetQuitPreparation() {
  GlobalBrowserCollection::GetInstance()->ForEach([](BrowserWindowInterface* browser) {
    UnloadController::From(browser)->ResetTryToCloseWindow();
    return true;
  }, BrowserCollection::Order::kCreation);
}
void FinishQuitPreparation(uint64_t generation, bool allowed) {
  auto& state = State();
  if (state.quit_generation != generation || !state.quit_preflight) return;
  auto completion = state.quit_preflight;
  state.quit_preflight = nil; state.quit_browser = nullptr;
  if (!allowed) ResetQuitPreparation();
  completion(allowed);
}
void ContinueQuitPreparation(uint64_t generation, bool proceed) {
  auto& state = State();
  if (state.quit_generation != generation || !state.quit_preflight) return;
  if (!proceed) { FinishQuitPreparation(generation, false); return; }
  state.quit_browser = nullptr;
  bool waiting = false;
  GlobalBrowserCollection::GetInstance()->ForEach([&](BrowserWindowInterface* browser) {
    Browser* candidate = browser->GetBrowserForMigrationOnly();
    state.quit_browser = candidate;
    if (UnloadController::From(browser)->TryToCloseWindow(false,
        base::BindRepeating([](uint64_t generation, Browser* candidate, bool allowed) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (State().quit_browser == candidate) ContinueQuitPreparation(generation, allowed);
          });
        }, generation, candidate))) {
      waiting = true;
    } else { state.quit_browser = nullptr; }
    return !waiting;
  }, BrowserCollection::Order::kCreation);
  if (waiting) return;
  const int downloads = DownloadCoreService::BlockingShutdownCountAllProfiles();
  if (downloads == 0) { FinishQuitPreparation(generation, true); return; }
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = @"Quit and cancel downloads?";
  alert.informativeText = [NSString stringWithFormat:@"%d download(s) are still in progress.", downloads];
  [alert addButtonWithTitle:@"Keep Browsing"];
  [alert addButtonWithTitle:@"Quit"];
  NSWindow* window = NSApp.keyWindow ?: [NSClassFromString(@"CrestRoot") windowForIdentifier:nil];
  if (window) {
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      FinishQuitPreparation(generation, response == NSAlertSecondButtonReturn);
    }];
  } else {
    FinishQuitPreparation(generation, [alert runModal] == NSAlertSecondButtonReturn);
  }
}
Page* FindPage(NSString* identifier) {
  auto found = State().pages.find(base::SysNSStringToUTF8(identifier));
  return found == State().pages.end() ? nullptr : found->second.get();
}
}  // namespace

@interface CrestChromiumHost : NSObject <CrestChromiumEngineHost>
@end

@implementation CrestChromiumHost
- (void)setBrowserObserver:(void (^)(NSDictionary<NSString*, id>*))observer {
  CHECK(NSThread.isMainThread);
  State().browser_observation = [observer copy];
}
- (BOOL)adoptPage:(NSString*)adoptionID asPage:(NSString*)pageID profile:(NSString*)profileID observer:(Observation)observer {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  const auto found = state.adoptions.find(base::SysNSStringToUTF8(adoptionID));
  const auto key = base::SysNSStringToUTF8(pageID);
  if (state.disposing || found == state.adoptions.end() || !found->second.contents || state.pages.contains(key)
      || found->second.profile != base::SysNSStringToUTF8(profileID)) return NO;
  auto* contents = found->second.contents.get();
  Browser* browser = nullptr;
  for (const auto& [id, owner] : state.browsers)
    if (owner->strip && owner->strip->GetIndexOfWebContents(contents) >= 0) { browser = owner->browser; break; }
  if (!browser) return NO;
  auto page = std::make_unique<Page>(contents, browser, found->second.profile, observer);
  Page* adopted = page.get();
  state.pages.emplace(key, std::move(page)); state.adoptions.erase(found);
  observer(@"created", @{});
  adopted->Publish();
  return YES;
}
- (void)rejectAdoption:(NSString*)adoptionID {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  auto found = state.adoptions.find(base::SysNSStringToUTF8(adoptionID));
  if (found == state.adoptions.end()) return;
  auto contents = found->second.contents; state.adoptions.erase(found);
  if (!contents) return;
  for (const auto& [id, owner] : state.browsers) {
    int index = owner->strip ? owner->strip->GetIndexOfWebContents(contents.get()) : -1;
    if (index >= 0) { owner->strip->DetachAndDeleteWebContentsAt(index); return; }
  }
}
- (BOOL)createPage:(NSString*)pageID profile:(NSString*)profileID window:(NSString*)windowID
      privateMode:(BOOL)privateMode sourceProfile:(NSString*)sourceProfileID
         observer:(Observation)observer {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  const std::string key = base::SysNSStringToUTF8(pageID);
  if (!state.root_profile || state.disposing || state.pages.contains(key) || state.creating_pages.contains(key)) return NO;
  // Reclaim observers only after their WebContents destruction callback returned.
  std::erase_if(state.pages, [](const auto& pair) { return !pair.second->web_contents(); });
  state.creating_pages.insert(key);
  const std::string profile_id = base::SysNSStringToUTF8(profileID);
  auto* manager = g_browser_process->profile_manager();
  CHECK(manager);
  if (privateMode && !sourceProfileID.length) { state.creating_pages.erase(key); return NO; }
  const std::string source_id = privateMode ? base::SysNSStringToUTF8(sourceProfileID) : profile_id;
  const base::FilePath path = manager->user_data_dir().AppendASCII("Crest-" + source_id);
  manager->CreateProfileAsync(path, base::BindOnce(
      [](std::string page_id, std::string profile_id, std::string window_id,
         bool private_mode, Observation observer, Profile* profile) {
        auto& state = State();
        state.creating_pages.erase(page_id);
        if (!profile || state.disposing) { observer(@"creation_failed", @{}); return; }
        if (!state.profiles.contains(profile_id)) {
          // The regular source owns the OTR profile and must outlive it. No
          // private profile path, session checkpoint, or browsing history is created.
          state.profile_leases[profile_id] = std::make_unique<ScopedProfileKeepAlive>(
              profile, ProfileKeepAliveOrigin::kAppWindow);
          state.profiles[profile_id] = private_mode ? profile->GetOffTheRecordProfile(
              Profile::OTRProfileID::CreateUnique("crest-" + profile_id), true) : profile;
        }
        Browser* browser = BrowserFor(profile_id, window_id);
        NavigateParams params(browser, GURL("about:blank"), ui::PAGE_TRANSITION_AUTO_TOPLEVEL);
        params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
        params.window_action = NavigateParams::WindowAction::kNoAction;
        Navigate(&params);
        auto* contents = params.navigated_or_inserted_contents.get();
        if (!contents) { observer(@"creation_failed", @{}); return; }
        state.pages.emplace(page_id, std::make_unique<Page>(contents, browser, profile_id, observer));
        observer(@"created", @{});
      }, key, profile_id, base::SysNSStringToUTF8(windowID), static_cast<bool>(privateMode), [observer copy]));
  return YES;
}
- (NSView*)viewForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  return page && page->web_contents() ? page->web_contents()->GetNativeView().GetNativeNSView() : nil;
}
- (BOOL)preparePage:(NSString*)pageID forWindow:(NSString*)windowID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents() || page->closing) return NO;
  Browser* target = BrowserFor(page->profile, base::SysNSStringToUTF8(windowID));
  if (!target) return NO;
  if (page->browser != target) {
    TabStripModel* source = page->browser->tab_strip_model();
    const int index = source->GetIndexOfWebContents(page->web_contents());
    if (index < 0) return NO;
    // Preserve TabModel, navigation history, renderer and extension identity.
    auto tab = source->DetachTabAtForInsertion(index);
    page->browser = target;
    target->tab_strip_model()->InsertDetachedTabAt(
        target->tab_strip_model()->count(), std::move(tab), AddTabTypes::ADD_ACTIVE);
  }
  const int index = target->tab_strip_model()->GetIndexOfWebContents(page->web_contents());
  if (index < 0) return NO;
  target->tab_strip_model()->ActivateTabAt(index);
  return YES;
}
- (void)didAttachPage:(NSString*)pageID window:(NSString*)windowID {
  CHECK(NSThread.isMainThread);
  if (Page* page = FindPage(pageID); page && page->web_contents()) {
    page->web_contents()->WasShown();
    page->web_contents()->Focus();
  }
}
- (void)didDetachPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  if (Page* page = FindPage(pageID); page && page->web_contents()) page->web_contents()->WasHidden();
}
- (BOOL)command:(NSString*)command page:(NSString*)pageID url:(NSString*)url {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents()) return NO;
  auto* contents = page->web_contents();
  auto& controller = contents->GetController();
  if ([command isEqualToString:@"engine.navigate"]) {
    GURL target(base::SysNSStringToUTF8(url ?: @""));
    if (!target.is_valid()) return NO;
    controller.LoadURL(target, content::Referrer(), ui::PAGE_TRANSITION_TYPED, std::string());
  } else if ([command isEqualToString:@"engine.back"]) {
    if (controller.CanGoBack()) controller.GoBack();
  } else if ([command isEqualToString:@"engine.forward"]) {
    if (controller.CanGoForward()) controller.GoForward();
  } else if ([command isEqualToString:@"engine.reload"]) {
    controller.Reload(content::ReloadType::NORMAL, true);
  } else if ([command isEqualToString:@"engine.stop"]) {
    contents->Stop();
  } else if ([command isEqualToString:@"engine.close_page"]) {
    const int index = page->browser->tab_strip_model()->GetIndexOfWebContents(contents);
    if (index < 0 || page->closing) return NO;
    page->closing = true;
    page->browser->tab_strip_model()->CloseWebContentsAt(index, 0);
  } else { return NO; }
  return YES;
}
- (void)disposePages:(NSArray<NSString*>*)pageIDs windows:(NSArray<NSString*>*)windowIDs
    releaseProfiles:(NSArray<NSString*>*)profileIDs {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  for (NSString* identifier in pageIDs) {
    auto found = state.pages.find(base::SysNSStringToUTF8(identifier));
    if (found == state.pages.end()) continue;
    auto* contents = found->second->web_contents();
    Browser* browser = found->second->browser;
    state.pages.erase(found);  // Remove callbacks before destroying WebContents.
    if (contents) {
      TabStripModel* strip = browser->tab_strip_model();
      int index = strip->GetIndexOfWebContents(contents);
      if (index >= 0) strip->DetachAndDeleteWebContentsAt(index);
    }
  }
  for (NSString* identifier in windowIDs) {
    const auto id = base::SysNSStringToUTF8(identifier);
    for (;;) {
      auto owner = std::find_if(state.browsers.begin(), state.browsers.end(),
          [&](const auto& entry) { return entry.second->window == id; });
      if (owner == state.browsers.end()) break;
      Browser* browser = owner->second->browser;
      TabStripModel* strip = browser->tab_strip_model();
      if (strip->empty()) browser->SynchronouslyDestroyBrowser();
      else for (int index = strip->count() - 1; index >= 0; --index) strip->DetachAndDeleteWebContentsAt(index);
    }
  }
  std::erase_if(state.adoptions, [](const auto& entry) { return !entry.second.contents; });
  for (NSString* identifier in profileIDs) {
    const std::string id = base::SysNSStringToUTF8(identifier);
    auto found = state.profiles.find(id);
    if (found == state.profiles.end()) continue;
    Profile* profile = found->second;
    // Native popups may still await core adoption. Revoke them with their owner.
    std::erase_if(state.adoptions, [&](const auto& entry) { return entry.second.profile == id; });
    for (;;) {
      auto owner = std::find_if(state.browsers.begin(), state.browsers.end(),
          [&](const auto& entry) { return entry.second->browser->GetProfile() == profile; });
      if (owner == state.browsers.end()) break;
      Browser* browser = owner->second->browser;
      TabStripModel* strip = browser->tab_strip_model();
      if (strip->empty()) browser->SynchronouslyDestroyBrowser();
      else for (int index = strip->count() - 1; index >= 0; --index) strip->DetachAndDeleteWebContentsAt(index);
    }
    state.profiles.erase(found);
    if (profile->IsOffTheRecord()) ProfileDestroyer::DestroyOTRProfileWhenAppropriate(profile);
    state.profile_leases.erase(id);
  }
}
- (void)disposePages {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  state.disposing = true;
  state.browser_observation = nil;
  state.adoptions.clear();
  state.pages.clear();
  // The core has stopped accepting work. Observer teardown precedes native destruction.
  while (!state.browsers.empty()) {
    Browser* browser = state.browsers.begin()->second->browser;
    TabStripModel* strip = browser->tab_strip_model();
    if (strip->empty()) {
      browser->SynchronouslyDestroyBrowser();
    } else {
      const int count = strip->count();
      for (int index = count - 1; index >= 0; --index) strip->DetachAndDeleteWebContentsAt(index);
    }
  }
  for (const auto& [id, profile] : state.profiles)
    if (profile->IsOffTheRecord()) ProfileDestroyer::DestroyOTRProfileWhenAppropriate(profile);
  state.profiles.clear();
  state.profile_leases.clear();
}
- (void)prepareToQuit:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  if (state.quit_preflight || state.disposing) { completion(NO); return; }
  state.quit_preflight = [completion copy];
  ContinueQuitPreparation(++state.quit_generation, true);
}
- (void)cancelQuitPreparation {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  ++state.quit_generation;
  auto completion = state.quit_preflight; state.quit_preflight = nil; state.quit_browser = nullptr;
  ResetQuitPreparation();
  if (completion) completion(NO);
}
- (void)completeQuit {
  State().quitting = true;
  [NSApp terminate:nil];
}
@end

namespace crest {
bool IsEnabled() { return base::CommandLine::ForCurrentProcess()->HasSwitch("crest-control-plane"); }
void OnBrowserWindowCreated(Browser* browser) {
  if (!State().bootstrap) {
    State().bootstrap = browser;
    State().root_profile = browser->GetProfile()->GetOriginalProfile();
  }
  if (State().started && State().creating_window.empty()) {
    const std::string key = "native/" + base::Uuid::GenerateRandomV4().AsLowercaseString();
    State().browsers.emplace(key, std::make_unique<BrowserOwner>(browser, std::string()));
  }
}
void OnBrowserWindowDestroyed(Browser* browser) {
  if (State().bootstrap == browser) State().bootstrap = nullptr;
  std::erase_if(State().browsers, [browser](const auto& pair) { return pair.second->browser == browser; });
  if (State().quit_browser == browser && State().quit_preflight) {
    State().quit_browser = nullptr;
    const auto generation = State().quit_generation;
    dispatch_async(dispatch_get_main_queue(), ^{ ContinueQuitPreparation(generation, true); });
  }
}
void EnsureCrestUIStarted(Browser* browser) {
  CHECK(NSThread.isMainThread);
  if (State().started) return;
  CHECK(base::CommandLine::ForCurrentProcess()->HasSwitch("user-data-dir"));
  NSString* framework = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"CrestChromiumUI.framework"];
  NSBundle* bundle = [NSBundle bundleWithPath:framework];
  NSError* error = nil;
  CHECK([bundle loadAndReturnError:&error]) << base::SysNSStringToUTF8(error.description);
  CHECK(NSClassFromString(@"CrestRoot"));
  State().started = true;
  [NSClassFromString(@"CrestRoot") startWithHost:[[CrestChromiumHost alloc] init]];
}
NSWindow* WindowForBrowser(Browser* browser) {
  if (!State().started) return nil;
  for (const auto& [key, owner] : State().browsers) {
    if (owner->browser == browser && !owner->window.empty())
      return [NSClassFromString(@"CrestRoot") windowForIdentifier:base::SysUTF8ToNSString(owner->window)];
  }
  if (!State().creating_window.empty())
    return [NSClassFromString(@"CrestRoot") windowForIdentifier:base::SysUTF8ToNSString(State().creating_window)];
  return [NSClassFromString(@"CrestRoot") windowForIdentifier:nil];
}
bool DeferQuit() {
  return IsEnabled() && State().started && !State().quitting && [NSClassFromString(@"CrestRoot") deferQuit];
}
}  // namespace crest
