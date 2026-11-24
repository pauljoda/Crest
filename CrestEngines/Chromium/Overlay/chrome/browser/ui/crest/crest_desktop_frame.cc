#include "chrome/browser/ui/crest/crest_desktop_frame.h"

#include <algorithm>
#include <utility>

#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/task/single_thread_task_runner.h"
#include "build/build_config.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/crest/crest_desktop_host.h"
#include "chrome/browser/ui/crest/crest_desktop_ui.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/mojom/page/draggable_region.mojom.h"
#include "third_party/skia/include/core/SkRegion.h"
#include "ui/base/hit_test.h"
#include "ui/base/page_transition_types.h"
#include "ui/display/display.h"
#include "ui/display/screen.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/gfx/draggable_region.h"
#include "ui/views/controls/webview/webview.h"
#include "ui/views/widget/widget.h"
#include "ui/views/window/client_view.h"
#include "ui/views/window/frame_view.h"
#include "url/gurl.h"

#if BUILDFLAG(IS_WIN)
#include "chrome/install_static/install_util.h"
#include "ui/base/win/shell.h"
#include "ui/views/widget/desktop_aura/desktop_native_widget_aura.h"
#include "ui/views/widget/desktop_aura/desktop_window_tree_host_win.h"
#include "ui/views/win/hwnd_util.h"
#endif

namespace crest {

namespace {

// The window a first launch opens, which fits a laptop's work area.
constexpr gfx::Size kInitialSize(1280, 820);
// The smallest window the sidebar and a page still fit.
constexpr gfx::Size kMinimumSize(640, 420);
// The band along the window's top edge that resizes it, which the system's
// own border no longer covers once the title bar is the interface's, and how
// far along that edge its corners reach.
constexpr int kTopResizeThickness = 5;
constexpr int kTopResizeCornerWidth = 16;
// How long a window asked to close waits for its interface to tell the core.
constexpr base::TimeDelta kCloseTimeout = base::Seconds(2);
// An interface whose renderer died loads again at once, as Chrome's WebUI
// toolbar recovers its own, but one that died kRestoresAtOnce times in a row,
// each within kRestoreSettle of the last, waits kRestoreRetry first, so an
// interface that cannot start never reloads in a loop.
constexpr int kRestoresAtOnce = 3;
constexpr base::TimeDelta kRestoreSettle = base::Seconds(10);
constexpr base::TimeDelta kRestoreRetry = base::Minutes(1);

// Orders the windows by when each was last the one in use.
uint64_t NextActivation() {
  static uint64_t activations = 0;
  return ++activations;
}

gfx::Rect InitialBounds() {
  const gfx::Rect work_area = display::Screen::Get()->GetPrimaryDisplay().work_area();
  gfx::Rect bounds(kInitialSize);
  bounds.set_width(std::min(bounds.width(), work_area.width()));
  bounds.set_height(std::min(bounds.height(), work_area.height()));
  bounds.set_origin(work_area.CenterPoint() - gfx::Vector2d(bounds.width() / 2, bounds.height() / 2));
  return bounds;
}

// The interface of the window `window` names.
GURL InterfaceURL(const std::string& window) {
  return GURL(std::string(kCrestDesktopURL) + "?window=" + window);
}

#if BUILDFLAG(IS_WIN)
// Keeps the system's frame, which gives the window its border, shadow,
// rounded corners, snapping and side and bottom resizing, without its title
// bar, as Chrome's own window does
// (BrowserDesktopWindowTreeHostWin::GetClientAreaInsets).
class DesktopTreeHost : public views::DesktopWindowTreeHostWin {
 public:
  using DesktopWindowTreeHostWin::DesktopWindowTreeHostWin;

  bool GetClientAreaInsets(gfx::Insets* insets, int frame_thickness) const override {
    if (!ShouldUseNativeFrame()) return false;
    if (GetWidget()->IsFullscreen()) {
      *insets = gfx::Insets();
      return true;
    }
    // A maximized window extends past the screen by the frame's thickness on
    // every side; any other keeps no non-client area along its top, where
    // Windows would otherwise draw its own title bar.
    const int top = GetWidget()->IsMaximized() ? frame_thickness : 0;
    *insets = gfx::Insets::TLBR(top, frame_thickness, frame_thickness, frame_thickness);
    return true;
  }

  bool GetDwmFrameInsetsInPixels(gfx::Insets* insets) const override {
    *insets = gfx::Insets();
    return true;
  }
};
#endif

}  // namespace

// The client area, all of it the interface. Where the interface marks
// `app-region: drag`, the point is the window's caption, which the system
// moves, snaps and maximizes on a double click.
class DesktopClientView : public views::ClientView {
 public:
  using ClientView::ClientView;

  void SetDraggableRegion(SkRegion region) { draggable_region_ = std::move(region); }
  bool IsDraggable(const gfx::Point& point) const { return draggable_region_.contains(point.x(), point.y()); }

  int NonClientHitTest(const gfx::Point& point) override {
    if (IsDraggable(point)) return HTCAPTION;
    return ClientView::NonClientHitTest(point);
  }

 private:
  SkRegion draggable_region_;
};

namespace {

// The frame around the client view, which draws nothing: the client view
// fills the window, and the frame answers only for the top resize band.
class DesktopFrameView : public views::FrameView {
 public:
  gfx::Rect GetBoundsForClientView() const override { return GetLocalBounds(); }
  gfx::Size GetMinimumSize() const override { return kMinimumSize; }

  int NonClientHitTest(const gfx::Point& point) override {
    if (!GetLocalBounds().Contains(point)) return HTNOWHERE;
    views::Widget* widget = GetWidget();
    if (!widget->IsMaximized() && !widget->IsFullscreen()) {
      const int edge = GetHTComponentForFrame(point, gfx::Insets::TLBR(kTopResizeThickness, 0, 0, 0),
                                              kTopResizeThickness, kTopResizeCornerWidth,
                                              widget->widget_delegate()->CanResize());
      if (edge != HTNOWHERE) return edge;
    }
    return widget->client_view()->NonClientHitTest(point);
  }
};

}  // namespace

DesktopFrame::DesktopFrame(std::string window, Profile* profile, bool launches)
    : window_(std::move(window)), launches_(launches) {
  SetCanResize(true);
  SetCanMaximize(true);
  SetCanMinimize(true);
  SetTitle(u"Crest");

  widget_ = std::make_unique<views::Widget>();
  widget_->AddObserver(this);
  views::Widget::InitParams params(views::Widget::InitParams::CLIENT_OWNS_WIDGET,
                                   views::Widget::InitParams::TYPE_WINDOW);
  params.name = "CrestWindow";
  params.delegate = this;
  params.bounds = InitialBounds();
#if BUILDFLAG(IS_WIN)
  auto* native_widget = new views::DesktopNativeWidgetAura(widget_.get());
  params.native_widget = native_widget;
  params.desktop_window_tree_host = new DesktopTreeHost(widget_.get(), native_widget);
#endif
  widget_->Init(std::move(params));
  InterceptClose();
#if BUILDFLAG(IS_WIN)
  // The installed Crest's windows are its own on the taskbar: they group and
  // pin with its Start menu shortcut, which Setup gives the app user model
  // ID of Crest's install mode.
  if (IsInstalledProduct()) {
    ui::win::SetAppIdForWindow(install_static::GetBaseAppId(), views::HWNDForWidget(widget_.get()));
  }
#endif

  // The interface goes into the client view the widget made, never in place
  // of it: the widget keeps the non-client view it built around that view.
  auto web_view = std::make_unique<views::WebView>(profile);
  content::WebContents* contents = web_view->GetWebContents();
  contents->SetDelegate(this);
  contents->SetSupportsDraggableRegions(true);
  Observe(contents);
  web_view->LoadInitialURL(InterfaceURL(window_));
  web_view_ = widget_->SetClientContentsView(std::move(web_view));
}

DesktopFrame::~DesktopFrame() {
  if (widget_) widget_->RemoveObserver(this);
}

content::WebContents* DesktopFrame::interface_contents() const {
  return web_view_ ? web_view_->GetWebContents() : nullptr;
}

base::DictValue DesktopFrame::State() const {
  base::DictValue state;
  state.Set("maximized", widget_->IsMaximized());
  state.Set("fullscreen", widget_->IsFullscreen());
  state.Set("active", active_);
  return state;
}

void DesktopFrame::Adopt(std::string window) {
  window_ = std::move(window);
  launches_ = false;
}

void DesktopFrame::Show(bool activates) {
  if (!activates) {
    widget_->ShowInactive();
    return;
  }
  widget_->Show();
  web_view_->RequestFocus();
}

void DesktopFrame::InterceptClose() {
  widget_->MakeCloseSynchronous(base::BindOnce(&DesktopFrame::CloseRequested, base::Unretained(this)));
}

void DesktopFrame::CloseRequested(views::Widget::ClosedReason reason) {
  // The widget takes the callback once per request.
  InterceptClose();
  if (finishing_ || close_timeout_.IsRunning()) return;
  if (!DesktopHost::Get().RequestClose(this)) {
    Finish();
    return;
  }
  close_timeout_.Start(FROM_HERE, kCloseTimeout, base::BindOnce(&DesktopFrame::Finish, base::Unretained(this)));
}

void DesktopFrame::Finish() {
  if (finishing_) return;
  finishing_ = true;
  close_timeout_.Stop();
  widget_->Hide();
  // The host lets the frame go, and its widget with it, once this turn is
  // done with them. The last window closing ends the browser, as Crest is its
  // windows.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<DesktopFrame> frame) {
                       if (!frame) return;
                       DesktopHost& host = DesktopHost::Get();
                       host.FrameClosed(frame.get());
                       if (!host.FrameInUse()) chrome::AttemptExit();
                     },
                     weak_factory_.GetWeakPtr()));
}

views::ClientView* DesktopFrame::CreateClientView(views::Widget* widget) {
  client_view_ = new DesktopClientView(widget, TransferOwnershipOfContentsView());
  return client_view_;
}

std::unique_ptr<views::FrameView> DesktopFrame::CreateFrameView(views::Widget* widget) {
  return std::make_unique<DesktopFrameView>();
}

// A press where the interface marks `app-region: drag` stays with the frame,
// which leaves it to the system to move, snap or maximize the window. Sent
// into the interface's native view, the press would be taken there and the
// window would never move; BrowserView keeps a web app's draggable region
// from its contents the same way.
bool DesktopFrame::ShouldDescendIntoChildForEventHandling(gfx::NativeView child, const gfx::Point& location) {
  if (!client_view_) return true;
  gfx::Point point = location;
  views::View::ConvertPointToTarget(widget_->GetRootView(), client_view_, &point);
  return !client_view_->IsDraggable(point);
}

// Only a close that skips the request, such as the system ending the
// session, closes the widget itself.
void DesktopFrame::OnWidgetClosing(views::Widget* widget) {
  Finish();
}

// The widget can still answer that it is active while it hears it is not, so
// the window's state follows what it hears.
void DesktopFrame::OnWidgetActivationChanged(views::Widget* widget, bool active) {
  active_ = active;
  if (active) activation_ = NextActivation();
  ReportState();
}

void DesktopFrame::OnWidgetBoundsChanged(views::Widget* widget, const gfx::Rect& new_bounds) {
  ReportState();
}

void DesktopFrame::ReportState() {
  const base::DictValue state = State();
  std::string serialized = base::WriteJson(state).value_or(std::string());
  if (serialized == reported_state_) return;
  reported_state_ = std::move(serialized);
  DesktopHost::Get().FrameStateChanged(this, state);
}

content::KeyboardEventProcessingResult DesktopFrame::PreHandleKeyboardEvent(
    content::WebContents* source,
    const input::NativeWebKeyboardEvent& event) {
  // Ctrl+Shift+F12 inspects the interface itself while it is being built;
  // F12 is the page's.
  constexpr int kInspectModifiers = blink::WebInputEvent::kControlKey | blink::WebInputEvent::kShiftKey;
  if (event.GetType() == input::NativeWebKeyboardEvent::Type::kRawKeyDown &&
      event.windows_key_code == ui::VKEY_F12 &&
      (event.GetModifiers() & blink::WebInputEvent::kKeyModifiers) == kInspectModifiers) {
    DevToolsWindow::OpenDevToolsWindow(source, DevToolsOpenedByAction::kUnknown);
    return content::KeyboardEventProcessingResult::HANDLED;
  }
  // The interface's commands run before its own views see their keys, but
  // for keys that edit text, which a focused field sees first.
  return DesktopHost::Get().OfferKey(this, event, KeyStage::kBeforeInterface, source)
             ? content::KeyboardEventProcessingResult::HANDLED
             : content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool DesktopFrame::HandleKeyboardEvent(content::WebContents* source, const input::NativeWebKeyboardEvent& event) {
  // A field let go of keys that edit text, so their command runs.
  return DesktopHost::Get().OfferKey(this, event, KeyStage::kLetGo, source);
}

// The interface draws its own menus; Chromium's would offer a page's actions
// on Crest's chrome.
bool DesktopFrame::HandleContextMenu(content::RenderFrameHost& render_frame_host,
                                     const content::ContextMenuParams& params) {
  return true;
}

void DesktopFrame::DraggableRegionsChanged(const std::vector<blink::mojom::DraggableRegionPtr>& regions,
                                           content::WebContents* contents) {
  if (client_view_) client_view_->SetDraggableRegion(gfx::DraggableRegionsToSkRegion(regions));
}

// The interface's renderer crashed or was killed, which let the window's
// pages go from their embeds. A renderer that ended normally was told to, as
// the browser quits. The interface loads again on a later turn: loading it
// from inside the renderer's death would reenter the renderer's host.
void DesktopFrame::PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) {
  if (status == base::TERMINATION_STATUS_NORMAL_TERMINATION || status == base::TERMINATION_STATUS_STILL_RUNNING) {
    return;
  }
  if (finishing_ || browser_shutdown::IsTryingToQuit() || browser_shutdown::HasShutdownStarted()) return;
  const base::TimeTicks now = base::TimeTicks::Now();
  if (now - interface_died_ >= kRestoreSettle) interface_deaths_ = 0;
  interface_died_ = now;
  const base::TimeDelta delay = ++interface_deaths_ <= kRestoresAtOnce ? base::TimeDelta() : kRestoreRetry;
  restore_timer_.Start(FROM_HERE, delay, base::BindOnce(&DesktopFrame::RestoreInterface, base::Unretained(this)));
}

void DesktopFrame::RestoreInterface() {
  content::WebContents* contents = interface_contents();
  // DevTools, say, may have loaded it again already.
  if (finishing_ || !contents || !contents->IsCrashed()) return;
  content::NavigationController::LoadURLParams params(InterfaceURL(window_));
  params.transition_type = ui::PAGE_TRANSITION_AUTO_TOPLEVEL;
  params.should_replace_current_entry = true;
  contents->GetController().LoadURLWithParams(params);
}

}  // namespace crest
