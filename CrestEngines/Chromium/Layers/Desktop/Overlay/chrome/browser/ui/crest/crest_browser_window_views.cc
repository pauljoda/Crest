// Crest's BrowserWindow where Chromium draws the interface (Windows, and
// Linux next): mostly inert, as on the Mac, since Crest's interface owns the
// chrome; window-level queries answer against the Crest window's widget,
// which every Browser showing pages in that window shares.

#include <algorithm>
#include <type_traits>

#include "base/functional/bind.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/crest/crest_browser_window.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/crest/crest_desktop_host.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_type.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/web_modal/modal_dialog_host.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/emoji/emoji_panel_helper.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/range/range.h"
#include "ui/native_theme/native_theme.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_delegate.h"

static_assert(!std::is_abstract_v<CrestBrowserWindow>);

namespace {

using crest::UnavailableFeature;

views::Widget* WidgetFor(const Browser* browser) {
  return crest::DesktopHost::Get().WidgetForBrowser(browser);
}

void Unavailable(UnavailableFeature feature) {
  crest::DesktopHost::Get().ShowUnavailable(feature);
}

class CrestAutofillBubbleHandler final : public autofill::AutofillBubbleHandler {
 public:
  autofill::AutofillBubbleBase* ShowSaveCreditCardBubble(content::WebContents*,
                                                         autofill::SaveCardBubbleController*,
                                                         bool) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowIbanBubble(content::WebContents*,
                                               autofill::IbanBubbleController*,
                                               bool,
                                               autofill::IbanBubbleType) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowOfferNotificationBubble(content::WebContents*,
                                                            autofill::OfferNotificationBubbleController*,
                                                            bool) override {
    return Refuse(UnavailableFeature::kAutofill);
  }
  autofill::AutofillBubbleBase* ShowSaveAutofillAiDataBubble(content::WebContents*,
                                                             autofill::AutofillAiImportDataController*) override {
    return Refuse(UnavailableFeature::kAutofillAI);
  }
  autofill::AutofillBubbleBase* ShowAutofillAiLocalSaveNotification(
      content::WebContents*,
      autofill::AutofillAiImportDataController*) override {
    return Refuse(UnavailableFeature::kAutofillAI);
  }
  autofill::AutofillBubbleBase* ShowSaveAddressProfileBubble(
      content::WebContents*,
      std::unique_ptr<autofill::SaveAddressBubbleController>,
      bool) override {
    return Refuse(UnavailableFeature::kAddressAutofill);
  }
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  autofill::AutofillBubbleBase* ShowAddressSignInPromo(content::WebContents*,
                                                       const autofill::AutofillProfile&) override {
    return Refuse(UnavailableFeature::kAddressAutofill);
  }
#endif
  autofill::AutofillBubbleBase* ShowUpdateAddressProfileBubble(
      content::WebContents*,
      std::unique_ptr<autofill::UpdateAddressBubbleController>,
      bool) override {
    return Refuse(UnavailableFeature::kAddressAutofill);
  }
  autofill::AutofillBubbleBase* ShowFilledCardInformationBubble(
      content::WebContents*,
      autofill::FilledCardInformationBubbleController*,
      bool) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollBubble(content::WebContents*,
                                                            autofill::VirtualCardEnrollBubbleController*,
                                                            bool) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollConfirmationBubble(
      content::WebContents*,
      autofill::VirtualCardEnrollBubbleController*) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowMandatoryReauthBubble(content::WebContents*,
                                                          autofill::MandatoryReauthBubbleController*,
                                                          bool,
                                                          autofill::MandatoryReauthBubbleType) override {
    return Refuse(UnavailableFeature::kAutofill);
  }
  autofill::AutofillBubbleBase* ShowSaveCardConfirmationBubble(content::WebContents*,
                                                               autofill::SaveCardBubbleController*) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowSaveIbanConfirmationBubble(content::WebContents*,
                                                               autofill::IbanBubbleController*) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowOmniboxAutofillBubble(content::WebContents*,
                                                          autofill::OmniboxAutofillBubbleController*) override {
    return Refuse(UnavailableFeature::kAutofill);
  }
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersBubble(content::WebContents*,
                                                               autofill::PaymentsChurnedUsersBubbleController*,
                                                               bool) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersConfirmationBubble(
      content::WebContents*,
      autofill::PaymentsChurnedUsersBubbleController*) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }
  autofill::AutofillBubbleBase* ShowWalletReminderNoticeBubble(content::WebContents*,
                                                               autofill::WalletReminderNoticeBubbleController*,
                                                               bool) override {
    return Refuse(UnavailableFeature::kPaymentAutofill);
  }

 private:
  static autofill::AutofillBubbleBase* Refuse(UnavailableFeature feature) {
    Unavailable(feature);
    return nullptr;
  }
};

}  // namespace

// --- CrestFindBar: Crest's interface draws find; Chromium only needs one. -----

FindBarController* CrestFindBar::GetFindBarController() const {
  return controller_;
}
void CrestFindBar::SetFindBarController(FindBarController* find_bar_controller) {
  controller_ = find_bar_controller;
}
void CrestFindBar::Show(bool animate, bool focus) {}
void CrestFindBar::Hide(bool animate) {}
void CrestFindBar::SetFocusAndSelection() {}
void CrestFindBar::ClearResults(const find_in_page::FindNotificationDetails& results) {}
void CrestFindBar::StopAnimation() {}
void CrestFindBar::MoveWindowIfNecessary() {}
void CrestFindBar::SetFindTextAndSelectedRange(const std::u16string& find_text, const gfx::Range& selected_range) {}
std::u16string_view CrestFindBar::GetFindText() const {
  return {};
}
gfx::Range CrestFindBar::GetSelectedRange() const {
  return {};
}
void CrestFindBar::UpdateUIForFindResult(const find_in_page::FindNotificationDetails& result,
                                         const std::u16string& find_text) {}
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

// --- CrestLocationBar: Crest's address field is the interface's. ------------

void CrestLocationBar::FocusLocation(bool is_user_initiated, bool clear_focus_if_failed) {}
void CrestLocationBar::FocusSearch() {}
void CrestLocationBar::AnnounceAlert(const std::u16string& announcement) {}
void CrestLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}
void CrestLocationBar::UpdateContentSettingsIcons() {
  // Chromium asks the Browser's location bar, which in its own window speaks
  // for the active tab. Every page a Crest window shows lives in its Browser, and the
  // one Crest shows need not be the tab Chromium calls active, so each page
  // checks its own site state; a page whose state did not change reports
  // nothing.
  TabStripModel* tabs = browser_->tab_strip_model();
  for (int index = 0; index < tabs->count(); ++index) {
    crest::UpdateSiteIndicators(tabs->GetWebContentsAt(index));
  }
}
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
bool CrestLocationBar::IsMouseHovered() const {
  return false;
}
bool CrestLocationBar::IsFocusWithin() const {
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

// --- CrestExclusiveAccessContext --------------------------------------------

CrestExclusiveAccessContext::CrestExclusiveAccessContext(Browser* browser) : browser_(browser) {}

CrestExclusiveAccessContext::~CrestExclusiveAccessContext() {
  HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);
}

Profile* CrestExclusiveAccessContext::GetProfile() {
  return browser_->GetProfile();
}

bool CrestExclusiveAccessContext::IsFullscreen() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->IsFullscreen();
}

void CrestExclusiveAccessContext::EnterFullscreen(const url::Origin& origin,
                                                  ExclusiveAccessBubbleType bubble_type,
                                                  FullscreenTabParams fullscreen_tab_params) {
  // Only a page's own request shows the page alone; the browser's keeps
  // Crest's chrome around the page.
  content::WebContents* contents = GetWebContentsForExclusiveAccess();
  if (contents && !exclusive_access_bubble::IsExclusiveAccessModeBrowserFullscreen(bubble_type)) {
    content_fullscreen_ = contents->GetWeakPtr();
    crest::ReportContentFullscreen(contents, true);
  }
  views::Widget* widget = WidgetFor(browser_);
  if (widget && !widget->IsFullscreen()) {
    widget->SetFullscreen(true);
    WindowFullscreenChanged(true);
  }
  UpdateExclusiveAccessBubble({.origin = origin, .type = bubble_type}, {});
}

void CrestExclusiveAccessContext::ExitFullscreen() {
  EndContentFullscreen();
  HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);
  views::Widget* widget = WidgetFor(browser_);
  if (widget && widget->IsFullscreen()) {
    widget->SetFullscreen(false);
    WindowFullscreenChanged(false);
  }
}

void CrestExclusiveAccessContext::WindowFullscreenChanged(bool entered) {
  ExclusiveAccessManager::From(browser_)->fullscreen_controller()->WindowFullscreenStateChanged();
  if (!entered) EndContentFullscreen();
}

void CrestExclusiveAccessContext::UpdateUIForTabFullscreen() {
  content::WebContents* contents = GetWebContentsForExclusiveAccess();
  FullscreenController* controller = ExclusiveAccessManager::From(browser_)->fullscreen_controller();
  if (contents && controller->exclusive_access_tab() == contents) {
    content_fullscreen_ = contents->GetWeakPtr();
    crest::ReportContentFullscreen(contents, true);
    return;
  }
  if (content_fullscreen_) page_left_fullscreen_window_ = base::TimeTicks::Now();
  EndContentFullscreen();
}

void CrestExclusiveAccessContext::EndContentFullscreen() {
  content::WebContents* contents = content_fullscreen_.get();
  content_fullscreen_.reset();
  if (contents) crest::ReportContentFullscreen(contents, false);
}

void CrestExclusiveAccessContext::UpdateExclusiveAccessBubble(const ExclusiveAccessBubbleParams& params,
                                                              ExclusiveAccessBubbleHideCallback first_hide_callback) {
  const bool closes = (!params.has_download && params.type == EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE) ||
                      exclusive_access_bubble::IsExclusiveAccessModeBrowserFullscreen(params.type);
  if (closes) {
    if (first_hide_callback) std::move(first_hide_callback).Run(ExclusiveAccessBubbleHideReason::kNotShown);
    HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);
    return;
  }
  ShowFullscreenDisclosure(params.origin, std::move(first_hide_callback));
}

bool CrestExclusiveAccessContext::IsExclusiveAccessBubbleDisplayed() const {
  return exclusive_access_bubble_visible_;
}

void CrestExclusiveAccessContext::OnExclusiveAccessUserInput() {}

content::WebContents* CrestExclusiveAccessContext::GetWebContentsForExclusiveAccess() {
  return browser_->tab_strip_model()->GetActiveWebContents();
}

bool CrestExclusiveAccessContext::CanUserEnterFullscreen() const {
  return true;
}

bool CrestExclusiveAccessContext::CanUserExitFullscreen() const {
  // A page leaving its fullscreen briefly leaves the window, so a tapped
  // Escape's release can read as held; the guard keeps the window's own.
  return base::TimeTicks::Now() - page_left_fullscreen_window_ > base::Milliseconds(2000);
}

// TODO(crest): the interface shows the page's origin and how to leave, as the
// Mac's disclosure panel does. Until then the disclosure is only its timing.
void CrestExclusiveAccessContext::ShowFullscreenDisclosure(const url::Origin& origin,
                                                           ExclusiveAccessBubbleHideCallback first_hide_callback) {
  HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason::kInterrupted);
  fullscreen_disclosure_hide_callback_ = std::move(first_hide_callback);
  exclusive_access_bubble_visible_ = true;
  fullscreen_disclosure_timer_.Start(
      FROM_HERE, ExclusiveAccessBubble::kShowTime,
      base::BindOnce(&CrestExclusiveAccessContext::HideFullscreenDisclosure, base::Unretained(this),
                     ExclusiveAccessBubbleHideReason::kTimeout));
}

void CrestExclusiveAccessContext::HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason reason) {
  fullscreen_disclosure_timer_.Stop();
  exclusive_access_bubble_visible_ = false;
  if (fullscreen_disclosure_hide_callback_) std::move(fullscreen_disclosure_hide_callback_).Run(reason);
}

// --- CrestModalDialogHost ---------------------------------------------------

CrestModalDialogHost::~CrestModalDialogHost() {
  for (auto& observer : observers_) observer.OnHostDestroying();
}

gfx::NativeView CrestModalDialogHost::GetHostView() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget ? widget->GetNativeView() : gfx::NativeView();
}

gfx::Point CrestModalDialogHost::GetDialogPosition(const gfx::Size& size) {
  views::Widget* widget = WidgetFor(browser_);
  const int width = widget ? widget->GetClientAreaBoundsInScreen().width() : 1280;
  return gfx::Point(std::max(0, (width - size.width()) / 2), 64);
}

gfx::Size CrestModalDialogHost::GetMaximumDialogSize() {
  views::Widget* widget = WidgetFor(browser_);
  return widget ? widget->GetClientAreaBoundsInScreen().size() : gfx::Size(1200, 760);
}

void CrestModalDialogHost::AddObserver(web_modal::ModalDialogHostObserver* observer) {
  observers_.AddObserver(observer);
}

void CrestModalDialogHost::RemoveObserver(web_modal::ModalDialogHostObserver* observer) {
  observers_.RemoveObserver(observer);
}

// --- CrestBrowserWindow -----------------------------------------------------

CrestBrowserWindow::CrestBrowserWindow(Browser* browser)
    : browser_(browser), modal_dialog_host_(browser), exclusive_access_context_(browser), location_bar_(browser) {
  crest::OnBrowserWindowCreated(browser);
}

CrestBrowserWindow::~CrestBrowserWindow() {
  // As Chromium's own windows do, the Browser's features go before the window.
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
  crest::OnBrowserWindowDestroyed(browser_);
}

bool CrestBrowserWindow::IsActive() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->IsActive();
}

bool CrestBrowserWindow::IsMaximized() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->IsMaximized();
}

bool CrestBrowserWindow::IsMinimized() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->IsMinimized();
}

bool CrestBrowserWindow::IsFullscreen() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->IsFullscreen();
}

gfx::NativeWindow CrestBrowserWindow::GetNativeWindow() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget ? widget->GetNativeWindow() : gfx::NativeWindow();
}

gfx::Rect CrestBrowserWindow::GetRestoredBounds() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget ? widget->GetRestoredBounds() : GetBounds();
}

ui::mojom::WindowShowState CrestBrowserWindow::GetRestoredState() const {
  return IsMaximized() ? ui::mojom::WindowShowState::kMaximized : ui::mojom::WindowShowState::kNormal;
}

gfx::Rect CrestBrowserWindow::GetBounds() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget ? widget->GetWindowBoundsInScreen() : gfx::Rect(0, 0, 1280, 820);
}

void CrestBrowserWindow::Show() {
  crest::EnsureCrestUIStarted(browser_);
  crest::OnEngineWindowShown(browser_, true);
}

void CrestBrowserWindow::Hide() {
  if (views::Widget* widget = WidgetFor(browser_); widget && crest::OwnsWindow(browser_)) widget->Hide();
}

bool CrestBrowserWindow::IsVisible() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->IsVisible();
}

void CrestBrowserWindow::ShowInactive() {
  crest::OnEngineWindowShown(browser_, false);
  if (views::Widget* widget = WidgetFor(browser_)) widget->ShowInactive();
}

void CrestBrowserWindow::Close() {
  // The BrowserView close protocol, minus the OS window: beforeunload gets a
  // veto, tabs close, and the empty Browser schedules its own deletion.
  UnloadController::From(browser_)->OnWindowClosing();
}

void CrestBrowserWindow::Activate() {
  if (crest::ReturnFromPictureInPicture(browser_->tab_strip_model()->GetActiveWebContents())) return;
  if (views::Widget* widget = WidgetFor(browser_)) widget->Activate();
}

void CrestBrowserWindow::Deactivate() {}

void CrestBrowserWindow::Maximize() {
  if (views::Widget* widget = WidgetFor(browser_); widget && crest::OwnsWindow(browser_)) widget->Maximize();
}

void CrestBrowserWindow::Minimize() {
  if (views::Widget* widget = WidgetFor(browser_); widget && crest::OwnsWindow(browser_)) widget->Minimize();
}

void CrestBrowserWindow::Restore() {
  if (views::Widget* widget = WidgetFor(browser_); widget && crest::OwnsWindow(browser_)) widget->Restore();
}

void CrestBrowserWindow::SetBounds(const gfx::Rect& bounds) {
  views::Widget* widget = WidgetFor(browser_);
  if (!widget || IsFullscreen() || !crest::OwnsWindow(browser_)) return;
  widget->SetBounds(bounds);
}

void CrestBrowserWindow::FlashFrame(bool flash) {
  if (views::Widget* widget = WidgetFor(browser_)) widget->FlashFrame(flash);
}

ui::ZOrderLevel CrestBrowserWindow::GetZOrderLevel() const {
  return ui::ZOrderLevel::kNormal;
}

void CrestBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {}

bool CrestBrowserWindow::IsOnCurrentWorkspace() const {
  return true;
}

bool CrestBrowserWindow::IsVisibleOnScreen() const {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->IsVisibleOnScreen();
}

void CrestBrowserWindow::SetTopControlsShownRatio(content::WebContents* web_contents, float ratio) {}

bool CrestBrowserWindow::DoBrowserControlsShrinkRendererSize(const content::WebContents* contents) const {
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
  return 0;
}

void CrestBrowserWindow::SetTopControlsGestureScrollInProgress(bool in_progress) {}

std::vector<StatusBubble*> CrestBrowserWindow::GetStatusBubbles() {
  return {};
}

void CrestBrowserWindow::UpdateTitleBar() {}

void CrestBrowserWindow::UpdateLoadingAnimations(bool is_visible) {}

void CrestBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                            content::WebContents* new_contents,
                                            int index,
                                            int reason) {}

void CrestBrowserWindow::OnTabDetached(content::WebContents* contents, bool was_active) {}

gfx::Size CrestBrowserWindow::GetContentsSize() const {
  return {};
}

void CrestBrowserWindow::SetContentsSize(const gfx::Size& size) {}

autofill::AutofillBubbleHandler* CrestBrowserWindow::GetAutofillBubbleHandler() {
  static CrestAutofillBubbleHandler* handler = new CrestAutofillBubbleHandler();
  return handler;
}

LocationBar* CrestBrowserWindow::GetLocationBar() const {
  return const_cast<CrestLocationBar*>(&location_bar_);
}

ui::AcceleratorProvider* CrestBrowserWindow::GetAcceleratorProvider() {
  return nullptr;
}

PinnedToolbarActions* CrestBrowserWindow::GetPinnedToolbarActions() {
  return nullptr;
}

// TODO(crest): the interface focuses its address field.
void CrestBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {}

void CrestBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {}
void CrestBrowserWindow::UpdateToolbar(content::WebContents* contents) {}
bool CrestBrowserWindow::UpdateToolbarSecurityState() {
  return false;
}
void CrestBrowserWindow::UpdateCustomTabBarVisibility(bool visible, bool animate) {}
void CrestBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {}
void CrestBrowserWindow::FocusToolbar() {}
void CrestBrowserWindow::ToolbarSizeChanged(bool is_animating) {}
void CrestBrowserWindow::TabDraggingStatusChanged(bool is_dragging) {}
void CrestBrowserWindow::LinkOpeningFromGesture(WindowOpenDisposition disposition) {}
void CrestBrowserWindow::FocusAppMenu() {}
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
void CrestBrowserWindow::ShowUpdateChromeDialog() {}

void CrestBrowserWindow::ShowIntentPickerBubble(std::vector<apps::IntentPickerAppInfo> app_info,
                                                bool show_stay_in_chrome,
                                                bool show_remember_selection,
                                                apps::IntentPickerBubbleType bubble_type,
                                                const std::optional<url::Origin>& initiating_origin,
                                                IntentPickerResponse callback) {
  // TODO(crest): the interface offers the apps; until then links stay in Crest.
  std::move(callback).Run(std::string(), apps::PickerEntryType::kUnknown,
                          apps::IntentPickerCloseReason::STAY_IN_CHROME, false);
}

void CrestBrowserWindow::ShowBookmarkBubble(const GURL& url, bool already_bookmarked) {}

ShowTranslateBubbleResult CrestBrowserWindow::ShowTranslateBubble(content::WebContents* contents,
                                                                  translate::TranslateStep step,
                                                                  const std::string& source_language,
                                                                  const std::string& target_language,
                                                                  translate::TranslateErrors error_type,
                                                                  bool is_user_gesture) {
  if (contents) Unavailable(UnavailableFeature::kTranslation);
  return {};
}

DownloadBubbleUIController* CrestBrowserWindow::GetDownloadBubbleUIController() {
  return nullptr;
}

// TODO(crest): the core asks about downloads in progress before a quit.
void CrestBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(int download_count,
                                                                 DownloadCloseType dialog_type,
                                                                 base::OnceCallback<void(bool)> callback) {
  std::move(callback).Run(true);
}

void CrestBrowserWindow::ShowAppMenu() {}
void CrestBrowserWindow::PreHandleDragUpdate(const content::DropData& drop_data, const gfx::PointF& point) {}
void CrestBrowserWindow::PreHandleDragExit() {}
void CrestBrowserWindow::HandleDragEnded() {}

// A command's keys reach the page first or not as its preference says, as
// the Mac's key monitor decides; the interface hands the shell the core's
// bindings for its window.
content::KeyboardEventProcessingResult CrestBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  return crest::DesktopHost::Get().OfferKey(browser_, event, crest::KeyStage::kBeforePage)
             ? content::KeyboardEventProcessingResult::HANDLED
             : content::KeyboardEventProcessingResult::NOT_HANDLED;
}

// The page let the key go, so the command it is bound to runs, as the Mac's
// menu bar runs it then.
bool CrestBrowserWindow::HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) {
  return crest::DesktopHost::Get().OfferKey(browser_, event, crest::KeyStage::kLetGo);
}

std::unique_ptr<FindBar> CrestBrowserWindow::CreateFindBar() {
  return std::make_unique<CrestFindBar>();
}

web_modal::WebContentsModalDialogHost* CrestBrowserWindow::GetWebContentsModalDialogHost() {
  return &modal_dialog_host_;
}

web_modal::WebContentsModalDialogHost* CrestBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return &modal_dialog_host_;
}

void CrestBrowserWindow::ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) {
  Unavailable(UnavailableFeature::kProfiles);
}

void CrestBrowserWindow::ShowHatsDialog(const std::string& site_id,
                                        const std::optional<std::string>& hats_histogram_name,
                                        const std::optional<uint64_t> hats_survey_ukm_id,
                                        base::OnceClosure success_callback,
                                        base::OnceClosure failure_callback,
                                        const SurveyBitsData& product_specific_bits_data,
                                        const SurveyStringData& product_specific_string_data) {}

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
  ui::ShowEmojiPanel();
}

std::unique_ptr<content::EyeDropper> CrestBrowserWindow::OpenEyeDropper(content::RenderFrameHost* frame,
                                                                        content::EyeDropperListener* listener) {
  Unavailable(UnavailableFeature::kEyeDropper);
  return {};
}

void CrestBrowserWindow::ShowCaretBrowsingDialog() {
  Unavailable(UnavailableFeature::kCaretBrowsing);
}

void CrestBrowserWindow::CreateTabSearchBubble() {}
void CrestBrowserWindow::CloseTabSearchBubble() {}

void CrestBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {
  Unavailable(UnavailableFeature::kPrivateBrowsing);
}

void CrestBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {
  Unavailable(UnavailableFeature::kPrivateBrowsing);
}

bool CrestBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}

bool CrestBrowserWindow::GetCanResize() {
  views::Widget* widget = WidgetFor(browser_);
  return widget && widget->widget_delegate() && widget->widget_delegate()->CanResize();
}

ui::mojom::WindowShowState CrestBrowserWindow::GetWindowShowState() const {
  if (IsFullscreen()) return ui::mojom::WindowShowState::kFullscreen;
  if (IsMinimized()) return ui::mojom::WindowShowState::kMinimized;
  if (IsMaximized()) return ui::mojom::WindowShowState::kMaximized;
  return ui::mojom::WindowShowState::kNormal;
}

void CrestBrowserWindow::ShowChromeLabs() {
  Unavailable(UnavailableFeature::kChromeLabs);
}

BrowserView* CrestBrowserWindow::AsBrowserView() {
  return nullptr;
}

void CrestBrowserWindow::DeleteBrowserWindow() {
  delete this;
}
