// Adapted from Mori (MIT), commit b5b29c2e29061f9b2009e8cc0b2756c6ad62bb20.
// Copyright (c) 2026 Mori contributors. See CrestEngines/Chromium/ThirdParty/Mori-LICENSE.
// Crest BrowserWindow: mostly inert (SwiftUI owns the chrome); window-level
// queries answer against the assigned native Crest NSWindow.

#include "chrome/browser/ui/crest/crest_browser_window.h"
#include <type_traits>
static_assert(!std::is_abstract_v<CrestBrowserWindow>);

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/share/share_attempt.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_type.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/sharing_message/sharing_dialog_data.h"
#include "components/web_modal/modal_dialog_host.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/gfx/range/range.h"
#include "chrome/browser/themes/theme_service.h"
#include "ui/native_theme/native_theme.h"
#include "ui/color/color_provider_manager.h"

// Swift-exported surface of CrestRoot (see CrestRoot.swift); declared locally so
// this window can route web-content key events through the same shortcut
// registry the app-level NSEvent monitor uses, without pulling in the bridge.
@interface CrestRoot : NSObject
+ (BOOL)handleShortcutEvent:(NSEvent*)event;
+ (void)toggleBookmarkForURL:(NSString*)url title:(NSString*)title;
+ (void)shareURL:(NSString*)url title:(NSString*)title;
+ (void)showQRCodeForURL:(NSString*)url title:(NSString*)title;
+ (void)translateURL:(NSString*)url;
+ (void)translateText:(NSString*)text;
+ (void)showNativeNotice:(NSString*)message icon:(NSString*)icon;
+ (void)showTabSearch;
+ (void)focusOmnibox;
@end

namespace {

// Crest's chrome shortcuts (⌘S toggle sidebar, ⌘T toggle omnibox, …) belong to
// the SwiftUI registry. Claim them here — in the browser's keyboard pre-handler
// — so they win *before* the focused web page or Chromium's own commands
// (Save Page As on ⌘S, New Tab on ⌘T) can act. This is what makes the
// shortcuts fire reliably while web content has focus, instead of racing the
// app-level NSEvent monitor and Chromium's native accelerators (the
// intermittent "needs two presses" behavior).
bool HandleCrestShortcut(const input::NativeWebKeyboardEvent& event) {
  // Only fire on the raw key-down; ignore synthesized char and key-up events.
  if (event.GetType() != input::NativeWebKeyboardEvent::Type::kRawKeyDown) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  if (!ns_event || ns_event.type != NSEventTypeKeyDown) {
    return false;
  }
  return [NSClassFromString(@"CrestRoot") handleShortcutEvent:ns_event] == YES;
}

NSString* OriginDisclosureLabel(const url::Origin& origin) {
  const std::string serialized_origin = origin.Serialize();
  if (serialized_origin.empty() || serialized_origin == "null") {
    return @"Crest Browser";
  }
  return base::SysUTF8ToNSString(serialized_origin);
}

void ConfigureDisclosureLabel(NSTextField* label,
                              NSFont* font,
                              NSColor* color) {
  label.font = font;
  label.textColor = color;
  label.backgroundColor = NSColor.clearColor;
  label.bordered = NO;
  label.editable = NO;
  label.selectable = NO;
  label.lineBreakMode = NSLineBreakByTruncatingMiddle;
}

class CrestAutofillBubbleHandler final : public autofill::AutofillBubbleHandler {
 public:
  CrestAutofillBubbleHandler() = default;
  ~CrestAutofillBubbleHandler() override = default;

  autofill::AutofillBubbleBase* ShowSaveCreditCardBubble(
      content::WebContents* web_contents,
      autofill::SaveCardBubbleController* controller,
      bool is_user_gesture) override {
    Notice(@"Payment autofill bubbles are not exposed in Crest yet.",
           @"creditcard");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowIbanBubble(
      content::WebContents* web_contents,
      autofill::IbanBubbleController* controller,
      bool is_user_gesture,
      autofill::IbanBubbleType bubble_type) override {
    Notice(@"Payment autofill bubbles are not exposed in Crest yet.",
           @"creditcard");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowOfferNotificationBubble(
      content::WebContents* web_contents,
      autofill::OfferNotificationBubbleController* controller,
      bool is_user_gesture) override {
    Notice(@"Autofill offer bubbles are not exposed in Crest yet.", @"tag");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowSaveAutofillAiDataBubble(
      content::WebContents* web_contents,
      autofill::AutofillAiImportDataController* controller) override {
    Notice(@"Autofill AI bubbles are not exposed in Crest yet.", @"sparkles");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowAutofillAiLocalSaveNotification(
      content::WebContents* web_contents,
      autofill::AutofillAiImportDataController* controller) override {
    Notice(@"Autofill AI bubbles are not exposed in Crest yet.", @"sparkles");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowSaveAddressProfileBubble(
      content::WebContents* web_contents,
      std::unique_ptr<autofill::SaveAddressBubbleController> controller,
      bool is_user_gesture) override {
    Notice(@"Address autofill bubbles are not exposed in Crest yet.",
           @"person.text.rectangle");
    return nullptr;
  }

#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  autofill::AutofillBubbleBase* ShowAddressSignInPromo(
      content::WebContents* web_contents,
      const autofill::AutofillProfile& autofill_profile) override {
    Notice(@"Address autofill sign-in is not exposed in Crest yet.",
           @"person.crop.circle.badge.plus");
    return nullptr;
  }
#endif

  autofill::AutofillBubbleBase* ShowUpdateAddressProfileBubble(
      content::WebContents* web_contents,
      std::unique_ptr<autofill::UpdateAddressBubbleController> controller,
      bool is_user_gesture) override {
    Notice(@"Address autofill bubbles are not exposed in Crest yet.",
           @"person.text.rectangle");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowFilledCardInformationBubble(
      content::WebContents* web_contents,
      autofill::FilledCardInformationBubbleController* controller,
      bool is_user_gesture) override {
    Notice(@"Payment autofill bubbles are not exposed in Crest yet.",
           @"creditcard");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowVirtualCardEnrollBubble(
      content::WebContents* web_contents,
      autofill::VirtualCardEnrollBubbleController* controller,
      bool is_user_gesture) override {
    Notice(@"Virtual card enrollment is not exposed in Crest yet.",
           @"creditcard.trianglebadge.exclamationmark");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowVirtualCardEnrollConfirmationBubble(
      content::WebContents* web_contents,
      autofill::VirtualCardEnrollBubbleController* controller) override {
    Notice(@"Virtual card enrollment is not exposed in Crest yet.",
           @"creditcard.trianglebadge.exclamationmark");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowMandatoryReauthBubble(
      content::WebContents* web_contents,
      autofill::MandatoryReauthBubbleController* controller,
      bool is_user_gesture,
      autofill::MandatoryReauthBubbleType bubble_type) override {
    Notice(@"Autofill reauthentication is not exposed in Crest yet.",
           @"lock.shield");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowSaveCardConfirmationBubble(
      content::WebContents* web_contents,
      autofill::SaveCardBubbleController* controller) override {
    Notice(@"Payment autofill bubbles are not exposed in Crest yet.",
           @"creditcard");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowSaveIbanConfirmationBubble(
      content::WebContents* web_contents,
      autofill::IbanBubbleController* controller) override {
    Notice(@"Payment autofill bubbles are not exposed in Crest yet.",
           @"creditcard");
    return nullptr;
  }

  autofill::AutofillBubbleBase* ShowOmniboxAutofillBubble(
      content::WebContents*, autofill::OmniboxAutofillBubbleController*) override {
    Notice(@"Autofill is not connected in this host.", @"person"); return nullptr;
  }
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersBubble(
      content::WebContents*, autofill::PaymentsChurnedUsersBubbleController*, bool) override {
    Notice(@"Payment autofill is not connected in this host.", @"creditcard"); return nullptr;
  }
 private:
  static void Notice(NSString* message, NSString* icon) {
    [NSClassFromString(@"CrestRoot") showNativeNotice:message icon:icon];
  }
};

}  // namespace

CrestBrowserWindow::CrestBrowserWindow(Browser* browser)
    : browser_(browser),
      modal_dialog_host_(browser),
      exclusive_access_context_(browser),
      location_bar_(browser) {
  crest::OnBrowserWindowCreated(browser);
}

// --- CrestFindBar --------------------------------------------------------------

FindBarController* CrestFindBar::GetFindBarController() const {
  return controller_;
}

void CrestFindBar::SetFindBarController(FindBarController* find_bar_controller) { controller_ = find_bar_controller; }

void CrestFindBar::Show(bool animate, bool focus) {}

void CrestFindBar::Hide(bool animate) {}

void CrestFindBar::SetFocusAndSelection() {}

void CrestFindBar::ClearResults( const find_in_page::FindNotificationDetails& results) {}

void CrestFindBar::StopAnimation() {}

void CrestFindBar::MoveWindowIfNecessary() {}

void CrestFindBar::SetFindTextAndSelectedRange( const std::u16string& find_text, const gfx::Range& selected_range) {}

std::u16string_view CrestFindBar::GetFindText() const {
  return {};
}

gfx::Range CrestFindBar::GetSelectedRange() const {
  return {};
}

void CrestFindBar::UpdateUIForFindResult( const find_in_page::FindNotificationDetails& result, const std::u16string& find_text) {}

void CrestFindBar::AudibleAlert() {}

bool CrestFindBar::IsFindBarVisible() const {
  return false;
}

void CrestFindBar::RestoreSavedFocus() {}

bool CrestFindBar::HasGlobalFindPasteboard() const {
  return false;
}

void CrestFindBar::UpdateFindBarForChangedWebContents() {}

bool CrestFindBar::CanPopulateFromSelectedText() {
  return false;
}

const FindBarTesting* CrestFindBar::GetFindBarTesting() const {
  return nullptr;
}

bool CrestFindBar::HasFocus() const {
  return false;
}

void CrestFindBar::CloseOverlappingBubbles() {}

views::Widget* CrestFindBar::GetHostWidget() {
  return nullptr;
}

// --- CrestLocationBar ---------------------------------------------------------

void CrestLocationBar::FocusLocation(bool is_user_initiated, bool clear_focus_if_failed) {}

void CrestLocationBar::FocusSearch() {}

void CrestLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}

void CrestLocationBar::UpdateContentSettingsIcons() {}

void CrestLocationBar::SaveStateToContents(content::WebContents* contents) {}

void CrestLocationBar::Revert() {}

OmniboxView* CrestLocationBar::GetOmniboxView() {
  return nullptr;
}

OmniboxPopupView* CrestLocationBar::GetOmniboxPopupView() {
  return nullptr;
}

OmniboxController* CrestLocationBar::GetOmniboxController() {
  return nullptr;
}

bool CrestLocationBar::ShouldCloseOmniboxPopup(ui::MouseEvent* event) {
  return false;
}

content::WebContents* CrestLocationBar::GetWebContents() {
  return nullptr;
}

LocationBarModel* CrestLocationBar::GetLocationBarModel() {
  return nullptr;
}

std::optional<bubble_anchor_util::AnchorConfiguration> CrestLocationBar::GetChipAnchor() {
  return {};
}

ChipController* CrestLocationBar::GetChipController() {
  return nullptr;
}

void CrestLocationBar::OnChanged() {}

void CrestLocationBar::UpdateWithoutTabRestore() {}

ui::TrackedElement* CrestLocationBar::GetAnchorOrNull() {
  return nullptr;
}

Browser* CrestLocationBar::GetBrowser() {
  return browser_;
}

Profile* CrestLocationBar::GetProfile() {
  return browser_ ? browser_->GetProfile() : nullptr;
}

bool CrestLocationBar::IsInitialized() const {
  return false;
}

bool CrestLocationBar::IsVisible() const {
  return false;
}

bool CrestLocationBar::IsDrawn() const {
  return false;
}

bool CrestLocationBar::IsFullscreen() const {
  return false;
}

bool CrestLocationBar::IsEditingOrEmpty() const {
  return false;
}

void CrestLocationBar::InvalidateLayout() {}

gfx::Rect CrestLocationBar::Bounds() const {
  return {};
}

gfx::Rect CrestLocationBar::BoundsInScreen() const {
  return {};
}

gfx::Size CrestLocationBar::MinimumSize() const {
  return {};
}

gfx::Size CrestLocationBar::PreferredSize() const {
  return {};
}

void CrestLocationBar::Update(content::WebContents* contents) {}

void CrestLocationBar::ResetTabState(content::WebContents* contents) {}

bool CrestLocationBar::HasSecurityStateChanged() {
  return false;
}

LocationBarTesting* CrestLocationBar::GetLocationBarForTesting() {
  return nullptr;
}

// --- CrestExclusiveAccessContext ---------------------------------------------

CrestExclusiveAccessContext::CrestExclusiveAccessContext(Browser* browser)
    : browser_(browser) {}

CrestExclusiveAccessContext::~CrestExclusiveAccessContext() {
  HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);
}

Profile* CrestExclusiveAccessContext::GetProfile() {
  return browser_->GetProfile();
}

bool CrestExclusiveAccessContext::IsFullscreen() const {
  NSWindow* window = crest::WindowForBrowser(browser_);
  return window && (window.styleMask & NSWindowStyleMaskFullScreen);
}

void CrestExclusiveAccessContext::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {
  NSWindow* window = crest::WindowForBrowser(browser_);
  if (window && !(window.styleMask & NSWindowStyleMaskFullScreen)) {
    [window toggleFullScreen:nil];
  }
  ShowFullscreenDisclosure(origin);
}

void CrestExclusiveAccessContext::ExitFullscreen() {
  HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);
  NSWindow* window = crest::WindowForBrowser(browser_);
  if (window && (window.styleMask & NSWindowStyleMaskFullScreen)) {
    [window toggleFullScreen:nil];
  }
}

void CrestExclusiveAccessContext::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
  const bool should_close_bubble =
      !params.has_download &&
      params.type == EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE;
  if (should_close_bubble) {
    if (first_hide_callback) {
      std::move(first_hide_callback)
          .Run(ExclusiveAccessBubbleHideReason::kNotShown);
    }
    HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);
    return;
  }
  ShowFullscreenDisclosure(params.origin, std::move(first_hide_callback));
}

bool CrestExclusiveAccessContext::IsExclusiveAccessBubbleDisplayed() const {
  return exclusive_access_bubble_visible_;
}

void CrestExclusiveAccessContext::OnExclusiveAccessUserInput() {
  NSPanel* panel = (__bridge NSPanel*)fullscreen_disclosure_;
  if (panel) {
    [panel orderFront:nil];
  }
}

content::WebContents* CrestExclusiveAccessContext::GetWebContentsForExclusiveAccess() {
  return browser_->tab_strip_model()->GetActiveWebContents();
}

bool CrestExclusiveAccessContext::CanUserEnterFullscreen() const {
  return true;
}

bool CrestExclusiveAccessContext::CanUserExitFullscreen() const {
  return true;
}

void CrestExclusiveAccessContext::ShowFullscreenDisclosure(
    const url::Origin& origin,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
  NSWindow* parent = crest::WindowForBrowser(browser_);
  if (!parent) {
    if (first_hide_callback) {
      std::move(first_hide_callback)
          .Run(ExclusiveAccessBubbleHideReason::kNotShown);
    }
    return;
  }

  HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);

  const NSRect parent_frame = parent.frame;
  const CGFloat width = std::min<CGFloat>(
      520.0, std::max<CGFloat>(320.0, parent_frame.size.width - 48.0));
  const CGFloat height = 72.0;
  const NSRect frame = NSMakeRect(NSMidX(parent_frame) - width / 2.0,
                                  NSMaxY(parent_frame) - height - 28.0,
                                  width, height);

  NSPanel* panel =
      [[NSPanel alloc] initWithContentRect:frame
                                 styleMask:NSWindowStyleMaskBorderless |
                                           NSWindowStyleMaskNonactivatingPanel
                                   backing:NSBackingStoreBuffered
                                     defer:NO];
  panel.opaque = NO;
  panel.backgroundColor = NSColor.clearColor;
  panel.hasShadow = YES;
  panel.ignoresMouseEvents = YES;
  panel.level = parent.level + 1;
  panel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary |
                             NSWindowCollectionBehaviorCanJoinAllSpaces |
                             NSWindowCollectionBehaviorTransient;

  NSView* container =
      [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)];
  container.wantsLayer = YES;
  container.layer.cornerRadius = 14.0;
  container.layer.masksToBounds = YES;
  container.layer.backgroundColor =
      [[NSColor colorWithCalibratedWhite:0.06 alpha:0.86] CGColor];

  NSTextField* title = [NSTextField labelWithString:@"Full screen"];
  title.frame = NSMakeRect(20.0, 45.0, width - 40.0, 18.0);
  ConfigureDisclosureLabel(
      title, [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold],
      NSColor.whiteColor);

  NSTextField* origin_label =
      [NSTextField labelWithString:OriginDisclosureLabel(origin)];
  origin_label.frame = NSMakeRect(20.0, 26.0, width - 40.0, 16.0);
  ConfigureDisclosureLabel(origin_label,
                           [NSFont systemFontOfSize:12.0
                                             weight:NSFontWeightRegular],
                           [NSColor colorWithCalibratedWhite:1.0 alpha:0.78]);

  NSTextField* instruction =
      [NSTextField labelWithString:@"Press Esc to exit full screen"];
  instruction.frame = NSMakeRect(20.0, 10.0, width - 40.0, 15.0);
  ConfigureDisclosureLabel(instruction,
                           [NSFont systemFontOfSize:11.0
                                             weight:NSFontWeightRegular],
                           [NSColor colorWithCalibratedWhite:1.0 alpha:0.58]);

  [container addSubview:title];
  [container addSubview:origin_label];
  [container addSubview:instruction];
  panel.contentView = container;

  [parent addChildWindow:panel ordered:NSWindowAbove];
  [panel orderFront:nil];

  fullscreen_disclosure_ = (__bridge_retained void*)panel;
  fullscreen_disclosure_hide_callback_ = std::move(first_hide_callback);
  exclusive_access_bubble_visible_ = true;
}

void CrestExclusiveAccessContext::HideFullscreenDisclosure(
    ExclusiveAccessBubbleHideReason reason) {
  NSPanel* panel = (__bridge_transfer NSPanel*)fullscreen_disclosure_;
  fullscreen_disclosure_ = nullptr;
  exclusive_access_bubble_visible_ = false;

  if (panel) {
    [panel.parentWindow removeChildWindow:panel];
    [panel orderOut:nil];
    [panel close];
  }

  if (fullscreen_disclosure_hide_callback_) {
    std::move(fullscreen_disclosure_hide_callback_).Run(reason);
  }
}

CrestBrowserWindow::~CrestBrowserWindow() {
  crest::OnBrowserWindowDestroyed(browser_);
}

// --- CrestModalDialogHost ----------------------------------------------------

CrestModalDialogHost::~CrestModalDialogHost() {
  for (auto& observer : observers_) {
    observer.OnHostDestroying();
  }
}

gfx::NativeView CrestModalDialogHost::GetHostView() const {
  return gfx::NativeView(crest::WindowForBrowser(browser_).contentView);
}

gfx::Point CrestModalDialogHost::GetDialogPosition(const gfx::Size& size) {
  NSView* content = crest::WindowForBrowser(browser_).contentView;
  const int width = content ? NSWidth(content.bounds) : 1280;
  return gfx::Point(std::max(0, (width - size.width()) / 2), 64);
}

gfx::Size CrestModalDialogHost::GetMaximumDialogSize() {
  NSView* content = crest::WindowForBrowser(browser_).contentView;
  if (!content) {
    return gfx::Size(1200, 760);
  }
  return gfx::Size(NSWidth(content.bounds), NSHeight(content.bounds));
}

void CrestModalDialogHost::AddObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.AddObserver(observer);
}

void CrestModalDialogHost::RemoveObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.RemoveObserver(observer);
}

bool CrestBrowserWindow::IsMaximized() const {
  return crest::WindowForBrowser(browser_).isZoomed;
}

bool CrestBrowserWindow::IsMinimized() const {
  return crest::WindowForBrowser(browser_).isMiniaturized;
}

bool CrestBrowserWindow::IsFullscreen() const {
  return (crest::WindowForBrowser(browser_).styleMask & NSWindowStyleMaskFullScreen) != 0;
}

void CrestBrowserWindow::Hide() { [crest::WindowForBrowser(browser_) orderOut:nil]; }

void CrestBrowserWindow::ShowInactive() {
  crest::OnEngineWindowShown(browser_, false);
  [crest::WindowForBrowser(browser_) orderFront:nil];
}

void CrestBrowserWindow::Deactivate() {}

void CrestBrowserWindow::Maximize() { if (!IsMaximized()) [crest::WindowForBrowser(browser_) zoom:nil]; }

void CrestBrowserWindow::Minimize() { [crest::WindowForBrowser(browser_) miniaturize:nil]; }

void CrestBrowserWindow::Restore() { [crest::WindowForBrowser(browser_) deminiaturize:nil]; }

void CrestBrowserWindow::FlashFrame(bool flash) {}

ui::ZOrderLevel CrestBrowserWindow::GetZOrderLevel() const {
  return ui::ZOrderLevel::kNormal;
}

void CrestBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {}

bool CrestBrowserWindow::IsOnCurrentWorkspace() const {
  return crest::WindowForBrowser(browser_).isOnActiveSpace;
}

bool CrestBrowserWindow::IsVisibleOnScreen() const {
  return (crest::WindowForBrowser(browser_).occlusionState & NSWindowOcclusionStateVisible) != 0;
}

void CrestBrowserWindow::SetTopControlsShownRatio(content::WebContents* web_contents, float ratio) {}

bool CrestBrowserWindow::DoBrowserControlsShrinkRendererSize( const content::WebContents* contents) const {
  return false;
}

ui::NativeTheme* CrestBrowserWindow::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* CrestBrowserWindow::GetThemeProvider() const {
  return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile());
}

const ui::ColorProvider* CrestBrowserWindow::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(nullptr, false));
}

int CrestBrowserWindow::GetTopControlsHeight() const {
  return {};
}

void CrestBrowserWindow::SetTopControlsGestureScrollInProgress(bool in_progress) {}

std::vector<StatusBubble*> CrestBrowserWindow::GetStatusBubbles() {
  return {};
}

void CrestBrowserWindow::UpdateTitleBar() {}

void CrestBrowserWindow::BookmarkBarStateChanged( BookmarkBar::AnimateChangeType change_type) {}

void CrestBrowserWindow::TemporarilyShowBookmarkBar(base::TimeDelta duration) {}

void CrestBrowserWindow::UpdateDevTools(content::WebContents* inspected_web_contents) {}

bool CrestBrowserWindow::CanDockDevTools() const {
  return false;
}

void CrestBrowserWindow::UpdateLoadingAnimations(bool is_visible) {}




void CrestBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents, content::WebContents* new_contents, int index, int reason) {}

void CrestBrowserWindow::OnTabDetached(content::WebContents* contents, bool was_active) {}

void CrestBrowserWindow::ZoomChangedForActiveTab(bool can_show_bubble) {}

bool CrestBrowserWindow::ShouldHideUIForFullscreen() const {
  return false;
}

bool CrestBrowserWindow::IsFullscreenBubbleVisible() const {
  return false;
}

bool CrestBrowserWindow::IsForceFullscreen() const {
  return false;
}

void CrestBrowserWindow::SetForceFullscreen(bool force_fullscreen) {}

gfx::Size CrestBrowserWindow::GetContentsSize() const {
  return {};
}

void CrestBrowserWindow::SetContentsSize(const gfx::Size& size) {}

void CrestBrowserWindow::UpdatePageActionIcon(PageActionIconType type) {}

autofill::AutofillBubbleHandler* CrestBrowserWindow::GetAutofillBubbleHandler() {
  static CrestAutofillBubbleHandler* handler = new CrestAutofillBubbleHandler();
  return handler;
}

void CrestBrowserWindow::ExecutePageActionIconForTesting(PageActionIconType type) {}

LocationBar* CrestBrowserWindow::GetLocationBar() const {
  return const_cast<CrestLocationBar*>(&location_bar_);
}

void CrestBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {
  [NSClassFromString(@"CrestRoot") focusOmnibox];
}

void CrestBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {}

void CrestBrowserWindow::UpdateToolbar(content::WebContents* contents) {}

bool CrestBrowserWindow::UpdateToolbarSecurityState() {
  return false;
}

void CrestBrowserWindow::UpdateCustomTabBarVisibility(bool visible, bool animate) {}

void CrestBrowserWindow::SetDevToolsScrimVisibility(bool visible) {}

void CrestBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {}

void CrestBrowserWindow::FocusToolbar() {}

void CrestBrowserWindow::ToolbarSizeChanged(bool is_animating) {}

void CrestBrowserWindow::TabDraggingStatusChanged(bool is_dragging) {}

void CrestBrowserWindow::LinkOpeningFromGesture(WindowOpenDisposition disposition) {}

void CrestBrowserWindow::FocusAppMenu() {}

void CrestBrowserWindow::FocusBookmarksToolbar() {}

void CrestBrowserWindow::FocusInactivePopupForAccessibility() {}

void CrestBrowserWindow::RotatePaneFocus(bool forwards) {}

void CrestBrowserWindow::FocusWebContentsPane() {
  if (content::WebContents* contents =
          browser_->tab_strip_model()->GetActiveWebContents()) {
    contents->Focus();
  }
}

bool CrestBrowserWindow::IsBookmarkBarVisible() const {
  return false;
}

bool CrestBrowserWindow::IsBookmarkBarAnimating() const {
  return false;
}

bool CrestBrowserWindow::IsTabStripEditable() const {
  return true;
}

void CrestBrowserWindow::DisableTabStripEditingForTesting() {}

bool CrestBrowserWindow::IsToolbarVisible() const {
  return false;
}

bool CrestBrowserWindow::IsToolbarShowing() const {
  return false;
}

bool CrestBrowserWindow::IsLocationBarVisible() const {
  return false;
}

SharingDialog* CrestBrowserWindow::ShowSharingDialog(content::WebContents* contents, SharingDialogData data) {
  content::WebContents* target =
      contents ? contents : browser_->tab_strip_model()->GetActiveWebContents();
  if (target) {
    [NSClassFromString(@"CrestRoot") shareURL:base::SysUTF8ToNSString(target->GetVisibleURL().spec())
                 title:base::SysUTF16ToNSString(target->GetTitle())];
  }
  return nullptr;
}

void CrestBrowserWindow::ShowUpdateChromeDialog() {}

void CrestBrowserWindow::ShowIntentPickerBubble( std::vector<apps::IntentPickerAppInfo> app_info, bool show_stay_in_chrome, bool show_remember_selection, apps::IntentPickerBubbleType bubble_type, const std::optional<url::Origin>& initiating_origin, IntentPickerResponse callback) {
  if (app_info.empty()) {
    std::move(callback).Run(std::string(), apps::PickerEntryType::kUnknown,
                            apps::IntentPickerCloseReason::STAY_IN_CHROME,
                            false);
    return;
  }

  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = @"Open this link in another app?";
  alert.informativeText = @"Choose an app or keep browsing in Crest.";
  alert.alertStyle = NSAlertStyleInformational;
  for (const auto& app : app_info) {
    [alert addButtonWithTitle:base::SysUTF8ToNSString(app.display_name)];
  }
  [alert addButtonWithTitle:@"Stay in Crest"];

  NSModalResponse response = [alert runModal];
  NSInteger selected = response - NSAlertFirstButtonReturn;
  if (selected >= 0 && selected < static_cast<NSInteger>(app_info.size())) {
    const auto& app = app_info[static_cast<size_t>(selected)];
    std::move(callback).Run(app.launch_name, app.type,
                            apps::IntentPickerCloseReason::OPEN_APP,
                            false);
    return;
  }
  std::move(callback).Run(std::string(), apps::PickerEntryType::kUnknown,
                          apps::IntentPickerCloseReason::STAY_IN_CHROME,
                          false);
}

void CrestBrowserWindow::ShowBookmarkBubble(const GURL& url, bool already_bookmarked) {
  const std::string spec = url.is_valid() ? url.spec() : std::string();
  NSString* title = @"";
  if (content::WebContents* contents =
          browser_->tab_strip_model()->GetActiveWebContents()) {
    title = base::SysUTF16ToNSString(contents->GetTitle());
  }
  [NSClassFromString(@"CrestRoot") toggleBookmarkForURL:base::SysUTF8ToNSString(spec) title:title];
}

sharing_hub::ScreenshotCapturedBubble* CrestBrowserWindow::ShowScreenshotCapturedBubble( content::WebContents* contents, const gfx::Image& image) {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Screenshot captured."
                        icon:@"camera.viewfinder"];
  return nullptr;
}

qrcode_generator::QRCodeGeneratorBubbleView* CrestBrowserWindow::ShowQRCodeGeneratorBubble(content::WebContents* contents, const GURL& url, bool show_back_button) {
  NSString* title = contents ? base::SysUTF16ToNSString(contents->GetTitle()) : @"";
  const std::string spec = url.is_valid()
                               ? url.spec()
                               : (contents ? contents->GetVisibleURL().spec()
                                           : std::string());
  [NSClassFromString(@"CrestRoot") showQRCodeForURL:base::SysUTF8ToNSString(spec) title:title];
  return nullptr;
}

send_tab_to_self::SendTabToSelfBubbleView* CrestBrowserWindow::ShowSendTabToSelfDevicePickerBubble(content::WebContents* contents) {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Send to device is not exposed in Crest yet."
                        icon:@"paperplane"];
  return nullptr;
}

send_tab_to_self::SendTabToSelfBubbleView* CrestBrowserWindow::ShowSendTabToSelfPromoBubble(content::WebContents* contents, bool show_signin_button) {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Send to device is not exposed in Crest yet."
                        icon:@"paperplane"];
  return nullptr;
}

sharing_hub::SharingHubBubbleView* CrestBrowserWindow::ShowSharingHubBubble( share::ShareAttempt attempt) {
  if (content::WebContents* contents =
          browser_->tab_strip_model()->GetActiveWebContents()) {
    [NSClassFromString(@"CrestRoot") shareURL:base::SysUTF8ToNSString(contents->GetVisibleURL().spec())
                 title:base::SysUTF16ToNSString(contents->GetTitle())];
  }
  return nullptr;
}

ShowTranslateBubbleResult CrestBrowserWindow::ShowTranslateBubble( content::WebContents* contents, translate::TranslateStep step, const std::string& source_language, const std::string& target_language, translate::TranslateErrors error_type, bool is_user_gesture) {
  if (contents) {
    [NSClassFromString(@"CrestRoot") translateURL:base::SysUTF8ToNSString(contents->GetVisibleURL().spec())];
  }
  return {};
}

void CrestBrowserWindow::StartPartialTranslate(const std::string& source_language, const std::string& target_language, const std::u16string& text_selection) {
  [NSClassFromString(@"CrestRoot") translateText:base::SysUTF16ToNSString(text_selection)];
}

DownloadBubbleUIController* CrestBrowserWindow::GetDownloadBubbleUIController() {
  return nullptr;
}

void CrestBrowserWindow::ConfirmBrowserCloseWithPendingDownloads( int download_count, UnloadController::DownloadCloseType dialog_type, base::OnceCallback<void(bool)> callback) {
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = download_count == 1
                          ? @"A download is still in progress."
                          : [NSString stringWithFormat:@"%d downloads are still in progress.",
                                                       download_count];
  alert.informativeText = @"Closing Crest now will cancel unfinished downloads.";
  alert.alertStyle = NSAlertStyleWarning;
  [alert addButtonWithTitle:@"Close Anyway"];
  [alert addButtonWithTitle:@"Keep Browsing"];
  NSModalResponse response = [alert runModal];
  std::move(callback).Run(response == NSAlertFirstButtonReturn);
}

void CrestBrowserWindow::ShowAppMenu() {
  NSMenu* appMenu = [[NSApp.mainMenu itemAtIndex:0] submenu];
  if (!appMenu) {
    return;
  }
  NSWindow* window = crest::WindowForBrowser(browser_);
  NSPoint point = window ? NSMakePoint(NSMidX(window.frame), NSMaxY(window.frame) - 40)
                         : NSMakePoint(24, 24);
  [appMenu popUpMenuPositioningItem:nil atLocation:point inView:nil];
}

void CrestBrowserWindow::PreHandleDragUpdate(const content::DropData& drop_data, const gfx::PointF& point) {}

void CrestBrowserWindow::PreHandleDragExit() {}

void CrestBrowserWindow::HandleDragEnded() {}

content::KeyboardEventProcessingResult CrestBrowserWindow::PreHandleKeyboardEvent( const input::NativeWebKeyboardEvent& event) {
  if (HandleCrestShortcut(event)) {
    return content::KeyboardEventProcessingResult::HANDLED;
  }
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool CrestBrowserWindow::HandleKeyboardEvent( const input::NativeWebKeyboardEvent& event) {
  // Chromium offers shortcuts to the document first. Its Views window would
  // then dispatch unhandled equivalents to AppKit; Crest owns that last step.
  NSEvent* native_event = event.os_event.Get();
  if (event.GetType() != input::NativeWebKeyboardEvent::Type::kRawKeyDown ||
      !native_event || native_event.type != NSEventTypeKeyDown ||
      !crest::WindowForBrowser(browser_).isKeyWindow) return false;
  return [NSApp.mainMenu performKeyEquivalent:native_event];
}

std::unique_ptr<FindBar> CrestBrowserWindow::CreateFindBar() {
  return std::make_unique<CrestFindBar>();
}

web_modal::WebContentsModalDialogHost*
CrestBrowserWindow::GetWebContentsModalDialogHost() {
  return &modal_dialog_host_;
}

web_modal::WebContentsModalDialogHost*
CrestBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return &modal_dialog_host_;
}

void CrestBrowserWindow::ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Profiles are not exposed in Crest yet."
                        icon:@"person.crop.circle"];
}

void CrestBrowserWindow::MaybeShowProfileSwitchIPH() {}

void CrestBrowserWindow::MaybeShowSupervisedUserProfileSignInIPH() {}

void CrestBrowserWindow::ShowHatsDialog( const std::string& site_id, const std::optional<std::string>& hats_histogram_name, const std::optional<uint64_t> hats_survey_ukm_id, base::OnceClosure success_callback, base::OnceClosure failure_callback, const SurveyBitsData& product_specific_bits_data, const SurveyStringData& product_specific_string_data) {}

ExclusiveAccessContext* CrestBrowserWindow::GetExclusiveAccessContext() {
  return &exclusive_access_context_;
}

std::string CrestBrowserWindow::GetWorkspace() const {
  return {};
}

bool CrestBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return false;
}

void CrestBrowserWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

std::unique_ptr<content::EyeDropper> CrestBrowserWindow::OpenEyeDropper( content::RenderFrameHost* frame, content::EyeDropperListener* listener) {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Eye dropper is not exposed in Crest yet."
                        icon:@"eyedropper"];
  return {};
}

void CrestBrowserWindow::ShowCaretBrowsingDialog() {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Caret browsing is not exposed in Crest yet."
                        icon:@"text.cursor"];
}

void CrestBrowserWindow::CreateTabSearchBubble() {
  [NSClassFromString(@"CrestRoot") showTabSearch];
}

void CrestBrowserWindow::CloseTabSearchBubble() {}

void CrestBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Private browsing is not exposed in Crest yet."
                        icon:@"eye.slash"];
}

void CrestBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Private browsing is not exposed in Crest yet."
                        icon:@"eye.slash"];
}

bool CrestBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}

bool CrestBrowserWindow::GetCanResize() {
  return false;
}

ui::mojom::WindowShowState CrestBrowserWindow::GetWindowShowState() const {
  return {};
}

void CrestBrowserWindow::ShowChromeLabs() {
  [NSClassFromString(@"CrestRoot") showNativeNotice:@"Chrome Labs is not exposed in Crest."
                        icon:@"flask"];
}

BrowserView* CrestBrowserWindow::AsBrowserView() {
  return nullptr;
}

void CrestBrowserWindow::DeleteBrowserWindow() {
  delete this;
}

// --- Real implementations against the assigned native Crest window -------------------

void CrestBrowserWindow::Show() {
  crest::EnsureCrestUIStarted(browser_);
  crest::OnEngineWindowShown(browser_, true);
}

void CrestBrowserWindow::Close() {
  // The BrowserView/WebUIBrowserWindow close protocol, minus the OS window:
  // beforeunload gets a veto, then tabs close (TabStripEmpty() re-enters
  // Close()), and an empty browser is destroyed synchronously.
  if (!UnloadController::From(browser_)->HandleBeforeClose()) {
    return;
  }
  UnloadController::From(browser_)->OnWindowClosing();
  if (!browser_->tab_strip_model()->empty()) {
    browser_->tab_strip_model()->CloseAllTabs();
    return;
  }
  browser_->SynchronouslyDestroyBrowser();
  // `this` is deleted.
}

bool CrestBrowserWindow::IsActive() const {
  return crest::WindowForBrowser(browser_).isKeyWindow;
}

void CrestBrowserWindow::Activate() {
  [crest::WindowForBrowser(browser_) makeKeyAndOrderFront:nil];
}

gfx::NativeWindow CrestBrowserWindow::GetNativeWindow() const {
  return gfx::NativeWindow(crest::WindowForBrowser(browser_));
}

gfx::Rect CrestBrowserWindow::GetBounds() const {
  NSWindow* window = crest::WindowForBrowser(browser_);
  if (!window) {
    return gfx::Rect(0, 0, 1280, 820);
  }
  NSRect f = window.frame;
  NSScreen* screen = window.screen ?: NSScreen.screens.firstObject;
  const CGFloat flipped_y = NSMaxY(screen.frame) - NSMaxY(f);
  return gfx::Rect(NSMinX(f), flipped_y, NSWidth(f), NSHeight(f));
}

gfx::Rect CrestBrowserWindow::GetRestoredBounds() const {
  return GetBounds();
}

ui::mojom::WindowShowState CrestBrowserWindow::GetRestoredState() const {
  return ui::mojom::WindowShowState::kNormal;
}

bool CrestBrowserWindow::IsVisible() const {
  return crest::WindowForBrowser(browser_).isVisible;
}

void CrestBrowserWindow::SetBounds(const gfx::Rect& bounds) {}

bool CrestLocationBar::IsMouseHovered() const { return false; }
bool CrestLocationBar::IsFocusWithin() const {
  NSResponder* responder = crest::WindowForBrowser(browser_).firstResponder;
  return [responder isKindOfClass:NSTextView.class] && ((NSTextView*)responder).isFieldEditor;
}
