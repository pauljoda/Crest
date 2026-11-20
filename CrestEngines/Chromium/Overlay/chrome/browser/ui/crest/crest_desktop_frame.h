#ifndef CHROME_BROWSER_UI_CREST_CREST_DESKTOP_FRAME_H_
#define CHROME_BROWSER_UI_CREST_CREST_DESKTOP_FRAME_H_

#include <memory>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "content/public/browser/web_contents_delegate.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_delegate.h"
#include "ui/views/widget/widget_observer.h"

class Profile;

namespace views {
class WebView;
class Widget;
}  // namespace views

namespace crest {

class DesktopClientView;

// One Crest window on the platforms whose interface Chromium draws: a widget
// whose whole client area is Crest's interface, which embeds the window's
// pages itself. The interface draws the title bar too: the system keeps the
// window's border, shadow and corners, the interface's `app-region: drag`
// areas move the window, and the interface draws the window's buttons from
// the state the frame reports. The core names the window by `window`.
//
// Closing is the interface's: however the window is asked to close (its
// button, Alt+F4, the taskbar), the interface first tells the core, then
// confirms with Finish(). A window whose interface does not answer closes
// after a moment anyway.
class DesktopFrame : public views::WidgetDelegate,
                     public views::WidgetObserver,
                     public content::WebContentsDelegate {
 public:
  // `launches` marks the window a launch opens before the core says which
  // saved window it is.
  DesktopFrame(std::string window, Profile* profile, bool launches);
  DesktopFrame(const DesktopFrame&) = delete;
  DesktopFrame& operator=(const DesktopFrame&) = delete;
  ~DesktopFrame() override;

  const std::string& window() const { return window_; }
  bool launches() const { return launches_; }
  // Becomes the saved window `window`, which a launch reopens.
  void Adopt(std::string window);
  views::Widget* widget() const { return widget_.get(); }
  // The view the interface draws in, which its coordinates are relative to.
  views::WebView* web_view() const { return web_view_; }
  // The interface's own contents.
  content::WebContents* interface_contents() const;
  // What the interface draws the window's buttons from: whether the window
  // is maximized, full screen, and the one in use.
  base::DictValue State() const;
  // When the window was last the one in use; later is greater.
  uint64_t activation() const { return activation_; }

  // Shows the window, in front of the others when `activates`.
  void Show(bool activates);
  // Closes the window now that the interface has told the core.
  void Finish();

  // views::WidgetDelegate:
  views::ClientView* CreateClientView(views::Widget* widget) override;
  std::unique_ptr<views::FrameView> CreateFrameView(views::Widget* widget) override;

  // views::WidgetObserver:
  void OnWidgetClosing(views::Widget* widget) override;
  void OnWidgetActivationChanged(views::Widget* widget, bool active) override;
  void OnWidgetBoundsChanged(views::Widget* widget, const gfx::Rect& new_bounds) override;

  // content::WebContentsDelegate:
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(content::WebContents* source,
                                                                const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(content::WebContents* source, const input::NativeWebKeyboardEvent& event) override;
  bool HandleContextMenu(content::RenderFrameHost& render_frame_host,
                         const content::ContextMenuParams& params) override;
  void DraggableRegionsChanged(const std::vector<blink::mojom::DraggableRegionPtr>& regions,
                               content::WebContents* contents) override;

 private:
  // Asked to close: the interface decides, and the window closes on its own
  // after kCloseTimeout if the interface never answers.
  void CloseRequested(views::Widget::ClosedReason reason);
  void InterceptClose();
  // Tells the interface when what State() answers changed.
  void ReportState();

  std::string window_;
  bool launches_;
  std::unique_ptr<views::Widget> widget_;
  raw_ptr<DesktopClientView> client_view_ = nullptr;
  raw_ptr<views::WebView> web_view_ = nullptr;
  std::string reported_state_;
  // Whether the window is the one in use, as its widget last said.
  bool active_ = false;
  uint64_t activation_ = 0;
  bool finishing_ = false;
  base::OneShotTimer close_timeout_;
  base::WeakPtrFactory<DesktopFrame> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_DESKTOP_FRAME_H_
