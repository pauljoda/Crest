#import <AuthenticationServices/AuthenticationServices.h>
#import <Cocoa/Cocoa.h>
#import "CrestChromiumHost.h"

#include <algorithm>
#include <map>
#include <cmath>
#include <memory>
#include <string>
#include <set>
#include <vector>
#include "base/check.h"
#include "base/apple/foundation_util.h"
#include "base/pickle.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/timer/timer.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/task/sequenced_task_runner.h"
#include "base/files/file_util.h"
#include "components/prefs/pref_service.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/nuke_profile_directory_utils.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_attributes_storage_observer.h"
#include "content/public/browser/browsing_data_remover.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "content/public/browser/restore_type.h"
#include "chrome/browser/ui/crest/crest_permission_prompt.h"
#include "chrome/browser/ui/crest/crest_extension_prompt.h"
#include "extensions/browser/crx_installer.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/extension_icon_image.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/manifest_handlers/icons_handler.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "extensions/common/permissions/permissions_data.h"
#include "extensions/common/permissions/permission_message.h"

#include "extensions/browser/install/crx_install_error.h"
#include "components/version_info/version_info.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_util.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/extensions/api/side_panel/side_panel_service.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "extensions/browser/event_router.h"
#include "extensions/browser/permissions/active_tab_permission_granter.h"
#include "extensions/common/command.h"
#include "extensions/common/api/extension_action/action_info.h"
#include "extensions/common/mojom/context_type.mojom.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/accelerators/command.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
#include "ui/events/keycodes/keyboard_code_conversion_mac.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_host_observer.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_widget_host_view.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "ui/gfx/image/image.h"
#include "extensions/browser/pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "base/time/time.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_types.h"
#include "components/zoom/zoom_controller.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "base/functional/bind.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_item_model.h"
#include "chrome/browser/ui/crest/crest_download_hooks.h"
#include "chrome/browser/download/download_confirmation_result.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/download_manager.h"
#include "ui/shell_dialogs/selected_file_info.h"
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
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/drop_data.h"
#include "net/base/apple/url_conversions.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/blocked_content/popup_blocker_tab_helper.h"
#include "components/security_state/content/security_state_tab_helper.h"
#include "content/public/browser/media_session.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "components/security_state/core/security_state.h"
#include "content/public/browser/ssl_status.h"
#include "net/base/net_errors.h"
#include "net/cert/x509_certificate.h"
#include "net/cert/x509_util.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "content/public/browser/global_routing_id.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "ui/base/page_transition_types.h"

@interface CrestRoot : NSObject
+ (void)startWithHost:(id<CrestChromiumEngineHost>)host;
+ (NSWindow*)windowForIdentifier:(NSString*)identifier;
+ (NSDictionary<NSString*, NSString*>*)reserveEngineWindowForProfile:(NSString*)profileID;
+ (void)presentEngineWindow:(NSString*)windowID space:(NSString*)spaceID focused:(BOOL)focused;
+ (BOOL)deferQuit;
+ (BOOL)reopen;
+ (BOOL)openExternalURLs:(NSArray<NSURL*>*)urls;
+ (void)routeSidePanel:(NSString*)extensionID page:(NSString*)pageID
               request:(CrestSidePanelRequest)request;
+ (void)routeDevTools:(NSString*)pageID;
+ (void)closeDevToolsPanel:(NSString*)pageID;
+ (void)showNativeNotice:(NSString*)message icon:(NSString*)icon;
+ (void)translateText:(NSString*)text;
+ (BOOL)openAuthenticationSession:(NSURL*)url window:(NSString*)windowID;
+ (void)closeAuthenticationSession:(NSString*)windowID;
@end

@interface CrestLinkMenuAction : NSObject
@property(copy) void (^run)(void);
- (void)invoke:(id)sender;
@end
@implementation CrestLinkMenuAction
- (void)invoke:(id)sender { if (self.run) self.run(); }
@end

// The window an extension action's popup is shown in.
//
// Crest does not use `NSPopover` for these. On macOS 27 the popover composites
// a translucent system material with whatever it hosts, so an extension
// painting an opaque `#181A1B` measured `#68555B` on screen — a white haze over
// the extension's own rendering. Neither an opaque page base nor an opaque
// browser surface changes that, and an opaque view behind the web contents
// occludes the renderer's remote layer and leaves the popup blank. This is a
// plain borderless window instead: nothing of Crest's is composited with the
// extension's document, so what the renderer paints is what reaches the screen.
//
// It becomes key so the popup's own fields can be typed into, and is added as a
// child of the Crest window it was anchored in, so it travels and orders with
// it. There is no arrow: the arrow of a system popover is filled with the
// popover's own background colour, and Crest does not know the colour an
// extension's document paints.
@interface CrestExtensionPopupWindow : NSWindow
@end
@implementation CrestExtensionPopupWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

namespace {
using Observation = void (^)(NSString*, NSDictionary<NSString*, id>*);
// AppKit hosting follows Mori's native ExtensionView bridge (MIT; see
// ThirdParty/Mori-LICENSE). Each instance belongs to one Crest page/profile.
class ExtensionPopup final : public extensions::ExtensionView,
                             public extensions::ExtensionHostObserver {
 public:
  ExtensionPopup(std::unique_ptr<extensions::ExtensionViewHost> host, NSView* anchor_view, NSRect anchor_rect)
      : host_(std::move(host)), anchor_view_(anchor_view), anchor_rect_(anchor_rect) {
    host_->set_view(this);
    host_->AddObserver(this);
    auto weak = weak_factory_.GetWeakPtr();
    host_->SetCloseHandler(base::BindOnce([](base::WeakPtr<ExtensionPopup> popup, extensions::ExtensionHost*) {
      dispatch_async(dispatch_get_main_queue(), ^{ if (popup) popup->Close(); });
    }, weak));
    window_ = [[CrestExtensionPopupWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kDefaultWidth, kDefaultHeight)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window_.releasedWhenClosed = NO;
    window_.opaque = NO;
    window_.backgroundColor = NSColor.clearColor;
    window_.hasShadow = YES;
    window_.movable = NO;
    window_.animationBehavior = NSWindowAnimationBehaviorNone;
    window_.collectionBehavior =
        NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;
    // A plain layer-backed container, not a vibrancy view: it contributes only
    // the rounded corners Crest's own controls use. The renderer's view is its
    // one subview, with nothing opaque between them, so the remote layer the
    // renderer draws into is never occluded.
    NSView* container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kDefaultWidth, kDefaultHeight)];
    container.wantsLayer = YES;
    container.layer.backgroundColor = NSColor.clearColor.CGColor;
    container.layer.cornerRadius = kCornerRadius;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    container.layer.masksToBounds = YES;
    container.autoresizesSubviews = YES;
    NSView* view = host_->host_contents()->GetNativeView().GetNativeNSView();
    view.frame = container.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:view];
    window_.contentView = container;
    host_->CreateRendererSoon();
  }
  ~ExtensionPopup() override { Close(); }
  void Close() {
    weak_factory_.InvalidateWeakPtrs();
    for (id monitor in monitors_) [NSEvent removeMonitor:monitor];
    monitors_ = nil;
    for (id observation in observations_) [[NSNotificationCenter defaultCenter] removeObserver:observation];
    observations_ = nil;
    if (window_) {
      if (NSWindow* parent = window_.parentWindow) [parent removeChildWindow:window_];
      [window_ orderOut:nil];
      window_.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
      [window_ close];
      window_ = nil;
    }
    if (host_) { host_->RemoveObserver(this); host_.reset(); }
  }
  gfx::NativeView GetNativeView() override { return host_ ? host_->host_contents()->GetNativeView() : gfx::NativeView(); }
  void ResizeDueToAutoResize(content::WebContents*, const gfx::Size& size) override {
    if (!window_) return;
    content_size_ = NSMakeSize(std::clamp(size.width(), 25, 800), std::clamp(size.height(), 25, 600));
    Position();
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (auto* view = frame->GetView()) view->EnableAutoResize(gfx::Size(25, 25), gfx::Size(800, 600));
  }
  bool HandleKeyboardEvent(content::WebContents*, const input::NativeWebKeyboardEvent&) override { return false; }
  void OnLoaded() override {
    NSWindow* parent = anchor_view_.window;
    if (!parent || !window_ || presented_) { if (!parent) Close(); return; }
    presented_ = true;
    Position();
    [parent addChildWindow:window_ ordered:NSWindowAbove];
    [window_ makeKeyAndOrderFront:nil];
    Observe(parent);
    if (host_) host_->host_contents()->Focus();
  }
  void OnExtensionHostDestroyed(extensions::ExtensionHost* host) override {
    if (host_.get() == host) host_.release();
    Close();
  }
 private:
  static constexpr CGFloat kDefaultWidth = 360;
  static constexpr CGFloat kDefaultHeight = 320;
  // The radius Crest's own controls use.
  static constexpr CGFloat kCornerRadius = 12;
  static constexpr CGFloat kAnchorGap = 6;
  static constexpr CGFloat kScreenMargin = 8;
  static constexpr unsigned short kEscapeKeyCode = 53;

  // Places the popup under the control it was opened from, flipping above it
  // and sliding along the screen when there is not room below or beside it.
  void Position() {
    NSWindow* parent = anchor_view_.window;
    if (!window_ || !parent) return;
    const NSRect anchor = [parent convertRectToScreen:[anchor_view_ convertRect:anchor_rect_ toView:nil]];
    NSRect visible = (parent.screen ?: NSScreen.mainScreen).visibleFrame;
    NSRect frame = NSMakeRect(NSMidX(anchor) - content_size_.width / 2,
                              NSMinY(anchor) - kAnchorGap - content_size_.height,
                              content_size_.width, content_size_.height);
    if (NSMinY(frame) < NSMinY(visible) + kScreenMargin) {
      const CGFloat above = NSMaxY(anchor) + kAnchorGap;
      if (above + content_size_.height <= NSMaxY(visible) - kScreenMargin) frame.origin.y = above;
      else frame.origin.y = NSMinY(visible) + kScreenMargin;
    }
    frame.origin.x = std::clamp(frame.origin.x, NSMinX(visible) + kScreenMargin,
                                std::max(NSMinX(visible) + kScreenMargin,
                                         NSMaxX(visible) - kScreenMargin - content_size_.width));
    [window_ setFrame:frame display:YES];
  }

  // Transient like the popover it replaces: a click outside it, Escape, the
  // window it belongs to moving, resizing or minimising, and Crest going to the
  // background all dismiss it. The extension closing its own popup, the host
  // being destroyed and the extension unloading come through the host.
  void Observe(NSWindow* parent) {
    auto weak = weak_factory_.GetWeakPtr();
    NSWindow* popup = window_;
    const NSEventMask clicks = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    monitors_ = @[
      [NSEvent addLocalMonitorForEventsMatchingMask:clicks | NSEventMaskKeyDown
                                            handler:^NSEvent*(NSEvent* event) {
        if (!weak) return event;
        if (event.type == NSEventTypeKeyDown) {
          if (event.keyCode != kEscapeKeyCode) return event;
          weak->Close();
          return nil;
        }
        if (event.window != popup) weak->Close();
        return event;
      }],
      [NSEvent addGlobalMonitorForEventsMatchingMask:clicks handler:^(NSEvent*) {
        if (weak) weak->Close();
      }],
    ];
    NSMutableArray* observations = [NSMutableArray array];
    auto dismiss = ^(NSNotification*) {
      dispatch_async(dispatch_get_main_queue(), ^{ if (weak) weak->Close(); });
    };
    for (NSNotificationName name in @[NSWindowDidResizeNotification, NSWindowDidMoveNotification,
                                      NSWindowDidMiniaturizeNotification, NSWindowWillCloseNotification])
      [observations addObject:[[NSNotificationCenter defaultCenter] addObserverForName:name object:parent
          queue:NSOperationQueue.mainQueue usingBlock:dismiss]];
    [observations addObject:[[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationDidResignActiveNotification object:NSApp
                     queue:NSOperationQueue.mainQueue usingBlock:dismiss]];
    observations_ = observations;
  }

  std::unique_ptr<extensions::ExtensionViewHost> host_;
  NSView* __weak anchor_view_;
  NSRect anchor_rect_;
  CrestExtensionPopupWindow* __strong window_ = nil;
  NSArray* __strong monitors_ = nil;
  NSArray* __strong observations_ = nil;
  NSSize content_size_ = NSMakeSize(kDefaultWidth, kDefaultHeight);
  bool presented_ = false;
  base::WeakPtrFactory<ExtensionPopup> weak_factory_{this};
};

// An extension side panel is a Crest split-row card, not a Views
// SidePanelEntry: Crest never instantiates Chrome's SidePanelCoordinator. Only
// the extension host and its view belong to Chromium; placement, sizing and
// dismissal are the core's, and the card owns this object's lifetime.
class ExtensionSidePanel final : public extensions::ExtensionView,
                                 public extensions::ExtensionHostObserver {
 public:
  ExtensionSidePanel(std::unique_ptr<extensions::ExtensionViewHost> host,
                     std::string extension_id, void (^closed)(void))
      : host_(std::move(host)), extension_id_(std::move(extension_id)), closed_([closed copy]) {
    container_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 600)];
    container_.autoresizesSubviews = YES;
    host_->set_view(this);
    host_->AddObserver(this);
    auto weak = weak_factory_.GetWeakPtr();
    // The panel's own document called window.close(), or the extension
    // retracted its entry. Either way the card goes away with it.
    host_->SetCloseHandler(base::BindOnce([](base::WeakPtr<ExtensionSidePanel> panel, extensions::ExtensionHost*) {
      dispatch_async(dispatch_get_main_queue(), ^{ if (panel) panel->Dismiss(); });
    }, weak));
    NSView* view = host_->host_contents()->GetNativeView().GetNativeNSView();
    view.frame = container_.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container_ addSubview:view];
    host_->CreateRendererSoon();
  }
  ~ExtensionSidePanel() override { Close(); }
  NSView* container() { return container_; }
  const std::string& extension_id() const { return extension_id_; }
  // The extension retracted its entry or unloaded. Tell the core to drop the
  // card; the panel document goes away with this object.
  void Retract() { Dismiss(); }
  void Close() {
    weak_factory_.InvalidateWeakPtrs();
    closed_ = nil;
    if (host_) { host_->RemoveObserver(this); host_.reset(); }
  }
  gfx::NativeView GetNativeView() override {
    return host_ ? host_->host_contents()->GetNativeView() : gfx::NativeView();
  }
  // The card is laid out by the row, so the panel document never resizes it.
  void ResizeDueToAutoResize(content::WebContents*, const gfx::Size&) override {}
  void RenderFrameCreated(content::RenderFrameHost*) override {}
  bool HandleKeyboardEvent(content::WebContents*, const input::NativeWebKeyboardEvent&) override { return false; }
  void OnLoaded() override {}
  void OnExtensionHostDestroyed(extensions::ExtensionHost* host) override {
    if (host_.get() == host) host_.release();
    Dismiss();
  }
 private:
  // Hands the dismissal to the core, which removes the card and then releases
  // this object. Nothing may touch `this` afterwards.
  void Dismiss() {
    void (^closed)(void) = closed_;
    Close();
    if (closed) closed();
  }
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  std::string extension_id_;
  void (^__strong closed_)(void);
  NSView* __strong container_ = nil;
  base::WeakPtrFactory<ExtensionSidePanel> weak_factory_{this};
};
// The docked DevTools frontend inside a Crest page card.
//
// Chromium owns the frontend WebContents and everything in it, including the
// undock and close buttons. This owns only the container the core mounts, so a
// dock-side or size change is a relayout of a card that is already on screen
// rather than a new one, and the resizing strategy the frontend publishes is
// kept here beside it.
class DevToolsPanel {
 public:
  explicit DevToolsPanel(content::WebContents* frontend)
      : frontend_(frontend->GetWeakPtr()) {
    container_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    container_.autoresizesSubviews = YES;
    NSView* view = frontend->GetNativeView().GetNativeNSView();
    view.frame = container_.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container_ addSubview:view];
  }
  NSView* container() { return container_; }
  bool hosts(content::WebContents* frontend) const {
    return frontend_ && frontend_.get() == frontend;
  }
  DevToolsContentsResizingStrategy strategy;

 private:
  base::WeakPtr<content::WebContents> frontend_;
  NSView* __strong container_ = nil;
};
class NativePermissionPrompt final : public permissions::PermissionPrompt {
 public:
  NativePermissionPrompt(NSWindow* window, Delegate* delegate)
      : delegate_(delegate->GetWeakPtr()), window_(window) {
    alert_ = [[NSAlert alloc] init];
    alert_.messageText = base::SysUTF8ToNSString(delegate->GetRequestingOrigin().spec());
    NSMutableArray* requests = [NSMutableArray array];
    for (const auto& request : delegate->Requests())
      [requests addObject:base::SysUTF16ToNSString(request->GetMessageTextFragment())];
    alert_.informativeText = [requests componentsJoinedByString:@"\n"];
    [alert_ addButtonWithTitle:@"Allow"];
    [alert_ addButtonWithTitle:@"Block"];
    [alert_ addButtonWithTitle:@"Not Now"];
    auto weak = weak_factory_.GetWeakPtr();
    [alert_ beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      if (!weak || !weak->delegate_) return;
      weak->responded_ = true;
      auto current_delegate = weak->delegate_;
      if (response == NSAlertFirstButtonReturn) current_delegate->Accept(std::monostate());
      else if (response == NSAlertSecondButtonReturn) current_delegate->Deny(std::monostate());
      else current_delegate->Dismiss(std::monostate());
    }];
  }
  ~NativePermissionPrompt() override {
    weak_factory_.InvalidateWeakPtrs();
    if (!responded_ && alert_.window.sheetParent) [window_ endSheet:alert_.window returnCode:NSModalResponseCancel];
  }
  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override { return kDestroyPromptButKeepRequestPending; }
  permissions::PermissionPromptDisposition GetPromptDisposition() const override { return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE; }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override { return std::nullopt; }
  bool ShouldFinalizeRequestAfterDecided() const override { return true; }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants() const override { return {}; }
  std::optional<permissions::feature_params::PermissionElementPromptPosition> GetPromptPosition() const override { return std::nullopt; }
 private:
  base::WeakPtr<Delegate> delegate_;
  NSWindow* __weak window_;
  NSAlert* __strong alert_;
  bool responded_ = false;
  base::WeakPtrFactory<NativePermissionPrompt> weak_factory_{this};
};
struct SitePermission {
  const char* key;
  const char* label;
  ContentSettingsType type;
  bool supports_ask;
};
const SitePermission kSitePermissions[] = {
  {"camera", "Camera", ContentSettingsType::MEDIASTREAM_CAMERA, true},
  {"microphone", "Microphone", ContentSettingsType::MEDIASTREAM_MIC, true},
  {"location", "Location", ContentSettingsType::GEOLOCATION, true},
  {"notifications", "Notifications", ContentSettingsType::NOTIFICATIONS, true},
  {"popups", "Automatic Pop-ups", ContentSettingsType::POPUPS, false},
  {"downloads", "Automatic Downloads", ContentSettingsType::AUTOMATIC_DOWNLOADS, true}
};
struct Page;
struct BrowserOwner;
struct NativeAdoption {
  base::WeakPtr<content::WebContents> contents;
  std::string profile;
};
struct PendingLinkNavigation {
  content::OpenURLParams request;
  base::WeakPtr<content::WebContents> source;
  std::string profile;
  uint64_t revision;
  uint64_t generation;
};
class ExtensionStateObserver;
class NativeProfileDeletion;
struct HostState {
  const base::Time started_at = base::Time::Now();
  std::map<std::string, std::unique_ptr<ExtensionStateObserver>> extension_observers;
  void (^extension_review)(NSDictionary<NSString*, id>*, NSWindow*, void (^)(BOOL, BOOL));
  Browser* bootstrap = nullptr;
  Profile* root_profile = nullptr;
  bool started = false;
  bool disposing = false;
  bool quitting = false;
  uint64_t close_generation = 0;
  void (^close_preflight)(BOOL);
  std::vector<std::string> close_pages;
  std::map<std::string, uint64_t> close_revisions;
  std::set<std::string> close_windows;
  std::string close_pending;
  size_t close_index = 0;
  uint64_t quit_generation = 0;
  Browser* quit_browser = nullptr;
  void (^quit_preflight)(BOOL);
  std::string creating_window;
  std::map<std::string, Profile*> profiles;
  std::map<std::string, std::unique_ptr<ScopedProfileKeepAlive>> profile_leases;
  std::map<std::string, std::string> creating_pages;
  std::set<std::string> deleting_profiles;
  std::map<std::string, std::unique_ptr<NativeProfileDeletion>> profile_deletions;
  std::map<std::string, std::unique_ptr<BrowserOwner>> browsers;
  std::map<std::string, std::unique_ptr<Page>> pages;
  // The action popup opened from a Space that has no page. A page's own popup
  // lives on the page; this one has no page to live on and only one can be
  // open at a time, because an action popup is transient.
  std::unique_ptr<ExtensionPopup> space_extension_popup;
  std::map<std::string, NativeAdoption> adoptions;
  std::map<std::string, PendingLinkNavigation> pending_link_navigations;
  void (^browser_observation)(NSDictionary<NSString*, id>*);
  void (^download_observation)(NSDictionary<NSString*, id>*);
  void (^download_destination)(NSDictionary<NSString*, id>*, void (^)(NSString*));
  // System sign-in requests from other apps, by the Quick Window running each.
  // Requests that arrive before the native root starts wait in `pending_*`.
  std::map<std::string, ASWebAuthenticationSessionRequest*> authentication_sessions;
  std::vector<ASWebAuthenticationSessionRequest*> pending_authentication_sessions;
};
HostState& State() { static base::NoDestructor<HostState> state; return *state; }

// System sign-in (`ASWebAuthenticationSession`). Chromium's own handler opens a
// Views popup Browser in the last-used engine profile; that profile belongs to
// no Space and the popup never appears, so the sign-in page loads where nobody
// can see it. Crest runs the session in a Quick Window of the Space an external
// link from the requesting app routes to, and completes it when that page
// reaches the requester's callback. The window shows the page's address and
// has no editable location, which is what the system API requires.
//
// An ephemeral-session request still uses the Space's profile: the API leaves
// honoring it to the browser, and a Space is Crest's unit of identity.
void EndAuthenticationSession(const std::string& window, NSURL* callback, bool close_window) {
  auto& sessions = State().authentication_sessions;
  auto found = sessions.find(window);
  if (found == sessions.end()) return;
  ASWebAuthenticationSessionRequest* request = found->second;
  sessions.erase(found);
  if (callback) {
    [request completeWithCallbackURL:callback];
  } else {
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodeCanceledLogin
                                             userInfo:nil]];
  }
  if (close_window)
    [NSClassFromString(@"CrestRoot") closeAuthenticationSession:base::SysUTF8ToNSString(window)];
}

// The system's sign-in broker hands out one request at a time and waits for
// the browser to finish it; a request left open when Crest quits would hold
// every later sign-in until the broker restarts.
void CancelAllAuthenticationSessions() {
  auto& state = State();
  std::vector<ASWebAuthenticationSessionRequest*> requests =
      std::move(state.pending_authentication_sessions);
  state.pending_authentication_sessions.clear();
  for (const auto& [window, request] : state.authentication_sessions) requests.push_back(request);
  state.authentication_sessions.clear();
  for (ASWebAuthenticationSessionRequest* request : requests) {
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodeCanceledLogin
                                             userInfo:nil]];
  }
}

void StartAuthenticationSession(ASWebAuthenticationSessionRequest* request) {
  if (State().disposing || State().quitting) {
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodePresentationContextInvalid
                                             userInfo:nil]];
    return;
  }
  NSString* window = NSUUID.UUID.UUIDString;
  State().authentication_sessions[base::SysNSStringToUTF8(window)] = request;
  if (![NSClassFromString(@"CrestRoot") openAuthenticationSession:request.URL window:window])
    EndAuthenticationSession(base::SysNSStringToUTF8(window), nil, false);
}


// Drops any open panel card for `extension_id` in `profile`, for one tab or
// for all of them. An extension that unloads or turns its entry off has no
// panel left to show.
void RetractSidePanels(Profile* profile, const std::string& extension_id,
                       std::optional<int> tab_id);

// Chromium owns the wipe, profile registry and crash-recoverable disk cleanup.
// Keep the profile alive until the wipe and deletion marker have both completed.
class NativeProfileDeletion final : public content::BrowsingDataRemover::Observer,
                                    public ProfileAttributesStorageObserver {
 public:
  NativeProfileDeletion(std::string id, base::FilePath path, void (^completion)(BOOL))
      : id_(std::move(id)), path_(std::move(path)), completion_([completion copy]) {}
  ~NativeProfileDeletion() override {
    if (remover_) remover_->RemoveObserver(this);
    if (observing_storage_) g_browser_process->profile_manager()->GetProfileAttributesStorage().RemoveObserver(this);
  }
  void Start(Profile* profile) {
    if (!profile || State().disposing) { Finish(false); return; }
    profile_ = profile;
    keep_alive_ = std::make_unique<ScopedProfileKeepAlive>(profile, ProfileKeepAliveOrigin::kProfileDeletionProcess);
    if (IsProfileDirectoryMarkedForDeletion(path_)) { Wipe(); return; }
    auto* manager = g_browser_process->profile_manager();
    manager->GetProfileAttributesStorage().AddObserver(this);
    observing_storage_ = true;
    // This first signs the profile out, preventing data deletion from being
    // propagated by Chromium Sync, and persists its deletion marker.
    manager->GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(path_,
        base::DoNothing(), ProfileMetrics::DELETE_PROFILE_SETTINGS);
  }
  void Wipe() {
    remover_ = profile_->GetBrowsingDataRemover();
    remover_->AddObserver(this);
    remover_->RemoveAndReply(base::Time(), base::Time::Max(),
        chrome_browsing_data_remover::WIPE_PROFILE,
        chrome_browsing_data_remover::ALL_ORIGIN_TYPES, this);
  }
  void OnBrowsingDataRemoverDone(uint64_t failures) override {
    remover_->RemoveObserver(this);
    remover_ = nullptr;
    if (failures || State().disposing) { Finish(false); return; }
    // Do not report success while the next-launch cleanup marker is only in RAM.
    g_browser_process->local_state()->CommitPendingWrite(base::BindOnce(
        &NativeProfileDeletion::Finish, weak_factory_.GetWeakPtr(), true));
  }
  void OnProfileWasRemoved(const base::FilePath& path, const std::u16string&) override {
    if (path != path_) return;
    g_browser_process->profile_manager()->GetProfileAttributesStorage().RemoveObserver(this);
    observing_storage_ = false;
    Wipe();
  }
  void Finish(bool success) {
    if (finished_) return;
    finished_ = true;
    auto id = id_;
    const bool may_retry_creation = !success && !IsProfileDirectoryMarkedForDeletion(path_);
    void (^reply)(BOOL) = completion_;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (may_retry_creation) State().deleting_profiles.erase(id);
      State().profile_deletions.erase(id);
      reply(success);
    });
  }
 private:
  std::string id_;
  base::FilePath path_;
  void (^completion_)(BOOL);
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive_;
  raw_ptr<Profile> profile_ = nullptr;
  raw_ptr<content::BrowsingDataRemover> remover_ = nullptr;
  bool observing_storage_ = false;
  bool finished_ = false;
  base::WeakPtrFactory<NativeProfileDeletion> weak_factory_{this};
};

// Re-states Crest's install affordance on every open Chrome Web Store listing.
void RefreshStoreButtons();

// Profile-scoped change and icon observation adapted from Mori (MIT).
class ExtensionStateObserver
    : public extensions::ExtensionRegistryObserver,
      public extensions::ExtensionActionDispatcher::Observer,
      public extensions::SidePanelService::Observer,
      public ToolbarActionsModel::Observer,
      public extensions::IconImage::Observer {
 public:
  static ExtensionStateObserver* Ensure(Profile* profile, const std::string& id) {
    auto& observers = State().extension_observers;
    if (!observers.contains(id)) observers[id] = std::unique_ptr<ExtensionStateObserver>(new ExtensionStateObserver(profile));
    return observers[id].get();
  }
  ~ExtensionStateObserver() override {
    extensions::ExtensionRegistry::Get(profile_)->RemoveObserver(this);
    if (dispatcher_observed_) extensions::ExtensionActionDispatcher::Get(profile_)->RemoveObserver(this);
    if (side_panel_observed_) extensions::SidePanelService::Get(profile_)->RemoveObserver(this);
    if (auto* model = ToolbarActionsModel::Get(profile_)) model->RemoveObserver(this);
  }
  // The best currently-loaded icon for an extension, preferring the action's
  // dynamic (chrome.action.setIcon) and declarative icons for `tab_id`, then
  // the manifest icon, then the action's default icon.
  NSImage* IconFor(const extensions::Extension& extension,
                   extensions::ExtensionAction* action,
                   int tab_id) {
    if (action) {
      gfx::Image explicit_icon = action->GetExplicitlySetIcon(tab_id);
      if (!explicit_icon.IsEmpty()) {
        return explicit_icon.ToNSImage();
      }
      gfx::Image declarative_icon = action->GetDeclarativeIcon(tab_id);
      if (!declarative_icon.IsEmpty()) {
        return declarative_icon.ToNSImage();
      }
    }
    auto it = icons_.find(extension.id());
    if (it != icons_.end()) {
      gfx::Image manifest_icon = it->second->image();
      if (!manifest_icon.IsEmpty()) {
        return manifest_icon.ToNSImage();
      }
    }
    if (action) {
      gfx::Image default_icon = action->GetDefaultIconImage();
      if (!default_icon.IsEmpty()) {
        return default_icon.ToNSImage();
      }
    }
    return nil;
  }

  // Whether an extension still has the files it was installed from.
  //
  // A tracked-preference enforcement reset clears `extensions.settings` and
  // garbage-collects the install directories, but an extension can also be
  // loaded from a directory the user has since moved or deleted. Chromium keeps
  // such an extension enabled in the registry and only discovers the loss when
  // a resource is requested, which for an action means the popup navigating to
  // its own ERR_FILE_NOT_FOUND page inside Crest's popup window. Crest offers no
  // action for one: it is missing, not broken.
  //
  // One stat per extension per registry change. `RebuildIcons` runs on every
  // registry change and drops the cache with the icons.
  bool IsAvailable(const extensions::Extension& extension,
                   extensions::ExtensionAction* action) {
    auto cached = availability_.find(extension.id());
    if (cached != availability_.end()) {
      return cached->second;
    }
    bool available =
        !extension.path().empty() && base::PathExists(extension.path());
    if (available && action) {
      // A default popup is the resource the action's own click needs. A popup
      // set at runtime cannot be checked here and does not need to be: the
      // directory it would be read from is the one just checked.
      const GURL popup =
          action->GetPopupUrl(extensions::ExtensionAction::kDefaultTabId);
      if (!popup.is_empty() &&
          extension.GetResource(popup.path()).GetFilePath().empty()) {
        available = false;
      }
    }
    availability_[extension.id()] = available;
    return available;
  }

  // extensions::ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext* browser_context,
                         const extensions::Extension* extension) override {
    RebuildIcons();
    PostExtensionsChanged();
  }
  void OnExtensionUnloaded(content::BrowserContext* browser_context,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason reason) override {
    RetractSidePanels(profile_, extension->id(), std::nullopt);
    RebuildIcons();
    PostExtensionsChanged();
  }
  void OnExtensionInstalled(content::BrowserContext* browser_context,
                            const extensions::Extension* extension,
                            bool is_update) override {
    RebuildIcons();
    PostExtensionsChanged();
  }
  void OnExtensionUninstalled(content::BrowserContext* browser_context,
                              const extensions::Extension* extension,
                              extensions::UninstallReason reason) override {
    RebuildIcons();
    PostExtensionsChanged();
  }

  // extensions::SidePanelService::Observer:
  // `chrome.sidePanel.setOptions` can retract an entry the core is showing.
  // Chromium hands over the extension's merged options, so an entry that no
  // longer resolves to an enabled document closes its card.
  void OnPanelOptionsChanged(
      const extensions::ExtensionId& extension_id,
      const extensions::api::side_panel::PanelOptions& options) override {
    if (options.enabled.value_or(true) && options.path && !options.path->empty()) return;
    RetractSidePanels(profile_, extension_id,
                      options.tab_id ? std::optional<int>(*options.tab_id) : std::nullopt);
  }
  void OnSidePanelServiceShutdown() override { side_panel_observed_ = false; }

  // extensions::ExtensionActionDispatcher::Observer:
  void OnExtensionActionUpdated(
      extensions::ExtensionAction* extension_action,
      content::WebContents* web_contents,
      content::BrowserContext* browser_context) override {
    PostExtensionsChanged();
  }
  void OnShuttingDown() override { dispatcher_observed_ = false; }

  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId& id) override {
    PostExtensionsChanged();
  }
  void OnToolbarActionRemoved(
      const ToolbarActionsModel::ActionId& id) override {
    PostExtensionsChanged();
  }
  void OnToolbarActionUpdated(
      const ToolbarActionsModel::ActionId& id) override {
    PostExtensionsChanged();
  }
  void OnToolbarModelInitialized() override { PostExtensionsChanged(); }
  void OnToolbarPinnedActionsChanged() override { PostExtensionsChanged(); }

  // extensions::IconImage::Observer:
  void OnExtensionIconImageChanged(extensions::IconImage* image) override {
    PostExtensionsChanged();
  }

 private:
  explicit ExtensionStateObserver(Profile* profile) : profile_(profile) {
    extensions::ExtensionRegistry::Get(profile_)->AddObserver(this);
    extensions::ExtensionActionDispatcher::Get(profile_)->AddObserver(this);
    dispatcher_observed_ = true;
    if (auto* panels = extensions::SidePanelService::Get(profile_)) {
      panels->AddObserver(this);
      side_panel_observed_ = true;
    }
    if (ToolbarActionsModel* model = ToolbarActionsModel::Get(profile_)) {
      model->AddObserver(this);
    }
    RebuildIcons();
  }

  static void PostExtensionsChanged() {
    // Coalesce changes and publish after registry/toolbar mutations finish.
    static bool queued = false;
    if (queued) return;
    queued = true;
    dispatch_async(dispatch_get_main_queue(), ^{
      queued = false;
      if (State().browser_observation && !State().disposing)
        State().browser_observation(@{@"extensionsChanged": @YES});
      RefreshStoreButtons();
    });
  }

  // Keeps one async-loading manifest icon per installed extension. IconImage
  // self-invalidates when its extension unloads, so the map is rebuilt on
  // every registry change.
  void RebuildIcons() {
    availability_.clear();
    auto* registry = extensions::ExtensionRegistry::Get(profile_);
    std::map<std::string, std::unique_ptr<extensions::IconImage>> next;
    for (const extensions::ExtensionSet* set :
         {&registry->enabled_extensions(), &registry->disabled_extensions()}) {
      for (const auto& extension : *set) {
        if (!extension->is_extension()) {
          continue;
        }
        auto existing = icons_.find(extension->id());
        if (existing != icons_.end() &&
            existing->second->is_valid()) {
          next[extension->id()] = std::move(existing->second);
          continue;
        }
        next[extension->id()] = std::make_unique<extensions::IconImage>(
            profile_, extension.get(),
            extensions::IconsInfo::GetIcons(extension.get()), 32,
            gfx::ImageSkia(), this);
      }
    }
    icons_ = std::move(next);
  }

  raw_ptr<Profile> profile_;
  bool dispatcher_observed_ = false;
  bool side_panel_observed_ = false;
  std::map<std::string, std::unique_ptr<extensions::IconImage>> icons_;
  std::map<std::string, bool> availability_;
};


void AdvancePageClosePreparation(uint64_t generation, bool allowed);

// Fixed, in-process export commands for exactly one WebContents. This opens no
// debugging socket and exposes no general protocol/evaluation entry point to UI.
class PageDocumentService final : public content::WebContentsObserver,
                                  public content::DevToolsAgentHostClient {
 public:
  explicit PageDocumentService(content::WebContents* contents)
      : content::WebContentsObserver(contents) {}
  ~PageDocumentService() override { Finish(nil, @"The page was closed."); }

  void Export(NSString* format, CGFloat width, void (^completion)(NSData*, NSString*)) {
    if (completion_) { completion(nil, @"An export is already in progress for this page."); return; }
    if (!web_contents() || !std::isfinite(width) || width < 0 || width > 6000 ||
        !([format isEqualToString:@"pdf"] || [format isEqualToString:@"png"] || [format isEqualToString:@"mhtml"])) {
      completion(nil, @"This page cannot be exported."); return;
    }
    format_ = [format copy]; width_ = width; completion_ = [completion copy];
    agent_ = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
    attached_ = agent_ && agent_->AttachClient(this);
    if (!attached_) { Finish(nil, @"The renderer could not prepare the export."); return; }
    timer_.Start(FROM_HERE, base::Seconds(45), base::BindOnce(
        [](PageDocumentService* service) { service->Finish(nil, @"The page export timed out."); },
        base::Unretained(this)));
    if ([format isEqualToString:@"pdf"]) {
      Send("Page.printToPDF", base::DictValue().Set("printBackground", true)
          .Set("preferCSSPageSize", true).Set("generateTaggedPDF", true));
    } else if ([format isEqualToString:@"mhtml"]) {
      Send("Page.captureSnapshot", base::DictValue().Set("format", "mhtml"));
    } else {
      measuring_ = true;
      Send("Page.getLayoutMetrics", base::DictValue());
    }
  }

  void DispatchProtocolMessage(content::DevToolsAgentHost*, base::span<const uint8_t> message) override {
    if (!completion_) return;
    if (message.size() > 96 * 1024 * 1024) { Finish(nil, @"The page export is too large."); return; }
    auto response = base::JSONReader::ReadDict(base::as_string_view(message), base::JSON_PARSE_RFC);
    if (!response || response->FindInt("id") != sequence_) return;
    const auto* result = response->FindDict("result");
    if (!result) { Finish(nil, @"Chromium could not export this document."); return; }
    if (measuring_) {
      measuring_ = false;
      const auto* dimensions = result->FindDict("cssContentSize");
      double width = dimensions ? dimensions->FindDouble("width").value_or(0) : 0;
      double height = dimensions ? dimensions->FindDouble("height").value_or(0) : 0;
      if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0) {
        Finish(nil, @"The page dimensions are unavailable."); return;
      }
      width = std::min(width, 6000.0); height = std::min(height, 24000.0);
      const double target = width_ > 0 ? width_ : std::min(width, 1600.0);
      auto clip = base::DictValue().Set("x", 0).Set("y", 0)
          .Set("width", width).Set("height", height).Set("scale", target / width);
      Send("Page.captureScreenshot", base::DictValue().Set("format", "png")
          .Set("fromSurface", true).Set("captureBeyondViewport", true).Set("clip", std::move(clip)));
      return;
    }
    const auto* encoded = result->FindString("data");
    if (!encoded) { Finish(nil, @"Chromium returned an empty document."); return; }
    NSString* text = base::SysUTF8ToNSString(*encoded);
    NSData* data = [format_ isEqualToString:@"mhtml"] ? [text dataUsingEncoding:NSUTF8StringEncoding]
        : [[NSData alloc] initWithBase64EncodedString:text options:0];
    if (!data.length || data.length > 64 * 1024 * 1024) { Finish(nil, @"The page export is empty or too large."); return; }
    Finish(data, nil);
  }
  void AgentHostClosed(content::DevToolsAgentHost*) override {
    attached_ = false; agent_.reset(); Finish(nil, @"The page was closed.");
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument())
      Finish(nil, @"The page navigated before its export finished.");
  }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    Finish(nil, @"The page renderer stopped.");
  }
  void WebContentsDestroyed() override { Finish(nil, @"The page was closed."); Observe(nullptr); }

 private:
  void Send(const char* method, base::DictValue params) {
    if (!completion_ || !agent_) return;
    auto json = base::WriteJson(base::DictValue().Set("id", ++sequence_)
        .Set("method", method).Set("params", std::move(params)));
    if (!json) { Finish(nil, @"The page export could not start."); return; }
    agent_->DispatchProtocolMessage(this, base::as_byte_span(*json));
  }
  void Finish(NSData* data, NSString* error) {
    auto completion = completion_;
    completion_ = nil; measuring_ = false; timer_.Stop();
    if (attached_ && agent_) { attached_ = false; agent_->DetachClient(this); }
    agent_.reset();
    // Swift may dispose this page from the completion; leave the protocol stack first.
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(data, error); });
  }
  scoped_refptr<content::DevToolsAgentHost> agent_;
  base::OneShotTimer timer_;
  bool attached_ = false;
  bool measuring_ = false;
  int sequence_ = 0;
  CGFloat width_ = 0;
  NSString* format_ = nil;
  void (^completion_)(NSData*, NSString*) = nil;
};

// Chrome Web Store listings. The store's own Add to Chrome button is inert in
// this baseline, so Crest owns that affordance: a script in an isolated world
// on the store's own host relabels the button and asks the core to run Crest's
// install review. The script is not a general scripting entry point — it is
// injected only into the store's own main frame in a regular profile, and the
// only request it can make is for the extension the page's own URL names.
bool IsWebStoreURL(const GURL& url) {
  return url.SchemeIs(url::kHttpsScheme) && url.host() == "chromewebstore.google.com";
}

// The extension a store detail URL names, or an empty string for any other
// store page. Chrome Web Store identifiers are 32 characters from a-p.
std::string WebStoreExtensionID(const GURL& url) {
  if (!IsWebStoreURL(url)) return std::string();
  const std::string_view path = url.path();
  std::vector<std::string_view> parts = base::SplitStringPiece(
      path, "/", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
  if (parts.size() < 2 || parts.front() != "detail") return std::string();
  std::string_view candidate = parts.back();
  if (candidate.size() != 32) return std::string();
  for (char character : candidate)
    if (character < 'a' || character > 'p') return std::string();
  return std::string(candidate);
}

// The isolated-world script. It uses DOM and CSSOM APIs only: the store's
// content policy rejects stylesheets and inline style attributes Crest would
// add to the markup, but script-driven property changes are not markup.
const char* CrestStoreScript() {
  return R"JS((function() {
  if (window.__crestStore) { window.__crestStore.render(); return; }
  var labels = { install: 'Add to Crest', installed: 'Added to Crest',
                 remove: 'Remove from Crest', busy: 'Installing…' };
  var state = { id: '', installed: false, busy: false };
  var adopted = null, hovering = false, pending = false;
  function detailID() {
    var match = /\/detail\/(?:[^\/]+\/)?([a-p]{32})(?:\/|$)/.exec(location.pathname);
    return match ? match[1] : '';
  }
  function label(button) { return button.querySelector('span[jsname="V67aGc"]') || button; }
  function text(node) { return (node.textContent || '').replace(/\s+/g, ' ').trim(); }
  // The store keeps the listing it navigated away from in the document and
  // only hides it, so anything that is not actually rendered is stale.
  function shown(element) {
    if (!element || !element.isConnected) return false;
    var rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  function installLabel(value) {
    return /^(add to|added to|remove from) (chrome|crest)$/i.test(value) || value === labels.busy;
  }
  // The listing's own install button: the one in the section that carries the
  // extension's title, so a related listing's button is never adopted.
  function locate() {
    if (shown(adopted)) return adopted;
    adopted = null; hovering = false;
    var headings = document.querySelectorAll('h1'), scope = null;
    for (var heading = 0; heading < headings.length; heading++) {
      if (!shown(headings[heading])) continue;
      scope = headings[heading].closest('section');
      break;
    }
    var buttons = (scope || document).querySelectorAll('button');
    for (var index = 0; index < buttons.length; index++) {
      var button = buttons[index];
      if (!shown(button) || !installLabel(text(label(button)))) continue;
      adopted = button;
      button.addEventListener('pointerenter', function() { hovering = true; render(); });
      button.addEventListener('pointerleave', function() { hovering = false; render(); });
      button.addEventListener('focus', function() { hovering = true; render(); });
      button.addEventListener('blur', function() { hovering = false; render(); });
      return button;
    }
    return null;
  }
  // The store's desktop layout keeps a minimum width wider than a Crest page
  // card, which pushes the listing and its install button past the card's
  // edge. Releasing that minimum lets the store use its own narrow layout.
  function relax() {
    // The store keeps the listing it navigated away from, so each document can
    // hold more than one of these; every one of them has to be released.
    var elements = [document.body].concat(
        Array.prototype.slice.call(document.querySelectorAll('header, main')));
    for (var index = 0; index < elements.length; index++) {
      var element = elements[index];
      if (!element) continue;
      var minimum = parseFloat(getComputedStyle(element).minWidth);
      if (minimum > 0 && minimum > window.innerWidth) element.style.minWidth = 'auto';
    }
  }
  // Crest installs extensions itself, so the store's prompts to switch to
  // Chrome are noise. Each prompt is found from its own wording and hidden at
  // the outermost element that still says nothing else, so the listing around
  // it is never affected.
  function hidePrompt(pattern, limit) {
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    var node;
    while ((node = walker.nextNode())) {
      if (!pattern.test(node.nodeValue || '')) continue;
      var element = node.parentElement, box = null;
      while (element && element !== document.body && text(element).length <= limit) {
        box = element;
        element = element.parentElement;
      }
      // A prompt the store re-rendered leaves the hidden original behind, so
      // a match that is already hidden is not the one to act on.
      if (!box || box.style.display === 'none') continue;
      box.style.display = 'none';
      return;
    }
  }
  var swept = 0, sweeping = 0;
  function hidePrompts() {
    // A prompt can be the last thing the store adds, so a suppressed sweep is
    // always retried rather than dropped.
    var waiting = 500 - (Date.now() - swept);
    if (waiting > 0) {
      if (!sweeping) sweeping = setTimeout(function() { sweeping = 0; hidePrompts(); }, waiting);
      return;
    }
    swept = Date.now();
    hidePrompt(/switch to chrome to install/i, 140);
    hidePrompt(/switch to chrome\?/i, 260);
  }
  function render() {
    relax();
    hidePrompts();
    var button = locate();
    if (!button) return;
    var wanted = state.busy ? labels.busy
        : (state.installed ? (hovering ? labels.remove : labels.installed) : labels.install);
    var span = label(button);
    if (text(span) !== wanted) span.textContent = wanted;
    if (button.disabled) button.disabled = false;
    button.removeAttribute('disabled');
    button.setAttribute('aria-disabled', state.busy ? 'true' : 'false');
    button.setAttribute('aria-label', wanted);
  }
  function schedule() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function() { pending = false; render(); });
  }
  // The core owns the install review, so the click never reaches the store's
  // own handler. The request names the extension the page itself is showing
  // and the core checks that name again before it downloads anything.
  function request() {
    var id = detailID();
    if (!id || state.busy) return;
    var command = state.installed ? 'crest-remove' : 'crest-install';
    if (!state.installed) { state.busy = true; render(); }
    history.replaceState(history.state, '',
        location.pathname + location.search + '#' + command + '=' + id);
  }
  document.addEventListener('click', function(event) {
    var button = locate();
    var target = event.target;
    if (!button || !target || !(target === button || (target.nodeType === 1 && button.contains(target)))) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    request();
  }, true);
  window.addEventListener('resize', function() { schedule(); });
  new MutationObserver(schedule).observe(document.documentElement,
      { childList: true, subtree: true, characterData: true });
  window.__crestStore = {
    render: render,
    apply: function(next) {
      state.id = next && typeof next.id === 'string' ? next.id : '';
      state.installed = !!(next && next.installed);
      state.busy = false;
      if (!adopted || !adopted.isConnected) { adopted = null; }
      render();
    }
  };
  render();
})();)JS";
}

// Crest's content bridges run in one isolated world of their own, as they do in
// WebKit's named content worlds: the page cannot see or call them. The bridges
// are written against WebKit's `webkit.messageHandlers.<name>.postMessage`, so
// the world defines that object itself and the bridge scripts run unchanged.
//
// A message leaves the world through a long poll. The host keeps one
// `__crestBridge.next()` evaluation outstanding per document; the engine
// resolves it when a bridge posts (the patched evaluator awaits promises in
// this world only) and the host at once asks for the next batch. Every batch and
// every evaluation names the document by a nonce the world minted, so nothing
// from a previous document is attributed to, or runs in, the next one.
constexpr char kContentBridgeShim[] = R"JS(
(() => {
  if (globalThis.__crestBridge) return null;
  const doc = Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const queue = [];
  let waiter = null;
  const flush = () => {
    if (!waiter || !queue.length) return;
    const resolve = waiter;
    waiter = null;
    resolve({ doc, messages: queue.splice(0) });
  };
  const handlers = new Map();
  const handler = (name) => {
    if (!handlers.has(name)) {
      handlers.set(name, Object.freeze({
        postMessage(body) {
          queue.push({ handler: name, body: JSON.parse(JSON.stringify(body ?? null)) });
          flush();
        },
      }));
    }
    return handlers.get(name);
  };
  globalThis.webkit = Object.freeze({
    messageHandlers: new Proxy({}, { get: (_, name) => typeof name === "string" ? handler(name) : undefined }),
  });
  globalThis.__crestBridge = Object.freeze({
    doc,
    next() { return new Promise((resolve) => { waiter = resolve; flush(); }); },
  });
  return doc;
})();
)JS";

std::string ContentFrameIdentifier(content::RenderFrameHost* frame, const std::string& doc) {
  const auto id = frame->GetGlobalId();
  return base::NumberToString(id.child_id.GetUnsafeValue()) + ":" +
         base::NumberToString(id.frame_routing_id) + ":" + doc;
}

struct Page final : content::WebContentsObserver, find_in_page::FindResultObserver,
                    favicon::FaviconDriverObserver, infobars::InfoBarManager::Observer,
                    media_session::mojom::MediaSessionObserver {
  Page(content::WebContents* contents, Browser* owner, std::string profile_id,
       Observation observer)
      : content::WebContentsObserver(contents), browser(owner),
        profile(std::move(profile_id)), observation([observer copy]) {
    find_helper = find_in_page::FindTabHelper::FromWebContents(contents);
    if (find_helper) find_helper->AddObserver(this);
    if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(contents)) driver->AddObserver(this);
    if (auto* media_session = content::MediaSession::Get(contents))
      media_session->AddObserver(media_receiver.BindNewPipeAndPassRemote());
    infobar_manager = infobars::ContentInfoBarManager::FromWebContents(contents);
    if (infobar_manager) {
      infobar_manager->AddObserver(this);
      // A page adopted from the engine may already carry bars.
      auto weak = contents->GetWeakPtr();
      std::vector<infobars::InfoBar*> existing(infobar_manager->infobars().begin(), infobar_manager->infobars().end());
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!weak || State().disposing) return;
        for (auto& [id, page] : State().pages) {
          if (page->web_contents() != weak.get()) continue;
          for (auto* bar : existing) page->PublishInfoBar(bar);
        }
      });
    }
  }
  ~Page() override {
    if (infobar_manager) infobar_manager->RemoveObserver(this);
    std::erase_if(State().pending_link_navigations, [&](const auto& entry) {
      return !entry.second.source || entry.second.source.get() == web_contents();
    });
    if (find_helper) find_helper->RemoveObserver(this);
    RemoveFaviconObservation();
  }
  void RemoveFaviconObservation() {
    if (web_contents())
      if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents())) driver->RemoveObserver(this);
  }
  void PublishFavicon(const gfx::Image& image) {
    if (!web_contents() || State().disposing) return;
    auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents());
    if (!driver) return;
    auto png = image.IsEmpty() ? nullptr : image.As1xPNGBytes();
    id data = NSNull.null;
    if (png && png->size() > 0 && png->size() <= 512 * 1024)
      data = [NSData dataWithBytes:png->front() length:png->size()];
    observation(@"favicon", @{ @"url": base::SysUTF8ToNSString(driver->GetActiveURL().spec()), @"data": data });
  }
  void OnFaviconUpdated(favicon::FaviconDriver*, NotificationIconType,
                       const GURL&, bool, const gfx::Image& image) override {
    PublishFavicon(image);
  }
  find_in_page::FindTabHelper* find_helper = nullptr;
  void (^find_completion)(BOOL) = nil;
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper*) override { find_helper = nullptr; find_completion = nil; }
  void OnFindResultAvailable(content::WebContents*) override {
    if (!find_helper || !find_completion || !find_helper->find_result().final_update()) return;
    auto completion = find_completion;
    find_completion = nil;
    completion(find_helper->find_result().number_of_matches() > 0);
  }
  Browser* browser;
  std::string profile;
  Observation observation;
  BOOL (^link_handler)(NSString*, NSString*, NSString*) = nil;
  CrestDeferredNavigation (^protected_link_handler)(NSString*) = nil;
  void (^modified_link_handler)(NSString*, NSUInteger, NSString*, void (^)(NSString*, CrestDeferredNavigation)) = nil;
  bool closing = false;
  // Whether a Chrome Web Store install or removal request from this page is
  // still with the core.
  bool store_request_open = false;
  uint64_t navigation_revision = 0;
  uint64_t navigation_generation = 0;
  std::unique_ptr<ExtensionPopup> extension_popup;
  std::unique_ptr<ExtensionSidePanel> side_panel;
  std::unique_ptr<DevToolsPanel> devtools;
  // A frontend Crest handed back to Chromium's own window. Its renderer is
  // permanently switched to Views drawing there, so re-docking must replace it
  // rather than mount it again.
  base::WeakPtr<content::WebContents> undocked_devtools;
  std::unique_ptr<PageDocumentService> document_service;
  // Content bridge sources, in install order, and whether each is limited to
  // the main frame.
  std::vector<std::pair<std::string, bool>> content_scripts;
  // Chromium's info bars — tab sharing, `chrome.debugger`, extension notices —
  // have no Views container here. Confirm bars are relayed for Crest to show
  // in the page; the rest carry no text of their own and stay silent.
  infobars::InfoBarManager* infobar_manager = nullptr;
  std::map<int, infobars::InfoBar*> infobars;
  int next_infobar_id = 0;
  void PublishInfoBar(infobars::InfoBar* bar) {
    if (!bar || State().disposing) return;
    auto* confirm = bar->delegate() ? bar->delegate()->AsConfirmInfoBarDelegate() : nullptr;
    if (!confirm) return;
    for (const auto& [id, known] : infobars) if (known == bar) return;
    const int id = ++next_infobar_id;
    infobars[id] = bar;
    const int buttons = confirm->GetButtons();
    NSString* ok = buttons & ConfirmInfoBarDelegate::BUTTON_OK
        ? base::SysUTF16ToNSString(confirm->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_OK)) : @"";
    NSString* cancel = buttons & ConfirmInfoBarDelegate::BUTTON_CANCEL
        ? base::SysUTF16ToNSString(confirm->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_CANCEL)) : @"";
    observation(@"infobar_added", @{ @"id": @(id), @"message": base::SysUTF16ToNSString(confirm->GetMessageText()),
        @"ok": ok, @"cancel": cancel, @"closeable": @(confirm->IsCloseable()) });
  }
  void OnInfoBarAdded(infobars::InfoBar* bar) override { PublishInfoBar(bar); }
  void OnInfoBarRemoved(infobars::InfoBar* bar, bool) override {
    for (auto it = infobars.begin(); it != infobars.end(); ++it) {
      if (it->second != bar) continue;
      const int id = it->first;
      infobars.erase(it);
      if (!State().disposing) observation(@"infobar_removed", @{ @"id": @(id) });
      return;
    }
  }
  void OnInfoBarReplaced(infobars::InfoBar* old_bar, infobars::InfoBar* new_bar) override {
    OnInfoBarRemoved(old_bar, false);
    PublishInfoBar(new_bar);
  }
  void OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) override {
    if (manager == infobar_manager) { manager->RemoveObserver(this); infobar_manager = nullptr; }
    infobars.clear();
  }
  // Runs the person's answer to a bar: accept, cancel or dismiss.
  bool RespondToInfoBar(int id, const std::string& response) {
    auto found = infobars.find(id);
    if (found == infobars.end() || !found->second->delegate()) return false;
    infobars::InfoBar* bar = found->second;
    auto* confirm = bar->delegate()->AsConfirmInfoBarDelegate();
    bool remove = false;
    if (response == "accept" && confirm) remove = confirm->Accept();
    else if (response == "cancel" && confirm) remove = confirm->Cancel();
    else if (response == "dismiss") { bar->delegate()->InfoBarDismissed(); remove = true; }
    else return false;
    if (remove) bar->RemoveSelf();
    return true;
  }
  // The engine's own Media Session — metadata, playback state and the actions
  // the page handles — reported in the event shape Crest's store reads, under
  // the document identifier Crest issued for the committed document.
  mojo::Receiver<media_session::mojom::MediaSessionObserver> media_receiver{this};
  media_session::mojom::MediaSessionInfoPtr media_info;
  std::optional<media_session::MediaMetadata> media_metadata;
  std::vector<media_session::mojom::MediaSessionAction> media_actions;
  std::string media_document;
  uint64_t media_sequence = 0;
  // The engine deactivates a session whose tab is muted; Crest keeps showing
  // it, muted, so the person can unmute it.
  bool media_seen_active = false;
  bool media_last_playing = false;
  void MediaSessionInfoChanged(media_session::mojom::MediaSessionInfoPtr info) override {
    media_info = std::move(info);
    PublishMediaSession();
  }
  void MediaSessionMetadataChanged(const std::optional<media_session::MediaMetadata>& metadata) override {
    media_metadata = metadata;
    PublishMediaSession();
  }
  void MediaSessionActionsChanged(const std::vector<media_session::mojom::MediaSessionAction>& actions) override {
    media_actions = actions;
    PublishMediaSession();
  }
  void MediaSessionImagesChanged(
      const base::flat_map<media_session::mojom::MediaSessionImageType,
                           std::vector<media_session::MediaImage>>&) override {}
  void MediaSessionPositionChanged(const std::optional<media_session::MediaPosition>&) override {}
  void OnAudioStateChanged(bool) override { PublishMediaSession(); }
  void DidUpdateAudioMutingState(bool) override { PublishMediaSession(); }
  void PublishMediaSession() {
    if (media_document.empty() || State().disposing || !web_contents()) return;
    using SessionState = media_session::mojom::MediaSessionInfo::SessionState;
    const bool engine_active = media_info && media_info->state != SessionState::kInactive;
    if (engine_active) {
      media_seen_active = true;
      media_last_playing = media_info->playback_state == media_session::mojom::MediaPlaybackState::kPlaying;
    }
    const bool active = engine_active || (media_info && media_seen_active && web_contents()->IsAudioMuted());
    // While muted the engine reports no playback; the last state it did report stands.
    NSString* playback = !active ? @"none" : media_last_playing ? @"playing" : @"paused";
    NSMutableArray* actions = [NSMutableArray array];
    for (auto action : media_actions) {
      switch (action) {
        case media_session::mojom::MediaSessionAction::kPlay: [actions addObject:@"play"]; break;
        case media_session::mojom::MediaSessionAction::kPause: [actions addObject:@"pause"]; break;
        case media_session::mojom::MediaSessionAction::kPreviousTrack: [actions addObject:@"previoustrack"]; break;
        case media_session::mojom::MediaSessionAction::kNextTrack: [actions addObject:@"nexttrack"]; break;
        default: break;
      }
    }
    auto text = [](const std::u16string& value) -> id {
      return value.empty() ? (id)NSNull.null : base::SysUTF16ToNSString(value);
    };
    observation(@"media_session", @{ @"body": @{
      @"version": @1, @"documentIdentifier": base::SysUTF8ToNSString(media_document),
      @"sequence": @(++media_sequence),
      @"location": base::SysUTF8ToNSString(web_contents()->GetLastCommittedURL().spec()),
      @"active": @(active),
      @"title": media_metadata ? text(media_metadata->title) : (id)NSNull.null,
      @"artist": media_metadata ? text(media_metadata->artist) : (id)NSNull.null,
      @"album": media_metadata ? text(media_metadata->album) : (id)NSNull.null,
      @"playbackState": playback,
      @"audible": @(web_contents()->IsCurrentlyAudible()),
      @"muted": @(web_contents()->IsAudioMuted()),
      @"actions": actions } });
  }
  // How many blocked pop-ups this document has already been reported.
  size_t published_blocked_popups = 0;
  void InjectContentScripts(content::RenderFrameHost* frame) {
    if (content_scripts.empty() || State().disposing || !frame || !frame->IsRenderFrameLive()) return;
    const bool main = frame->IsInPrimaryMainFrame();
    if (!main && frame->GetMainFrame() != web_contents()->GetPrimaryMainFrame()) return;
    std::string script = kContentBridgeShim;
    script = "(() => { const doc = " + script + " if (doc === null) return null;\n";
    for (const auto& [source, main_frame_only] : content_scripts) {
      if (main_frame_only && !main) continue;
      script += "try {\n" + source + "\n} catch (_) {}\n";
    }
    script += "return doc; })()";
    const auto id = frame->GetGlobalId();
    auto weak = web_contents()->GetWeakPtr();
    frame->ExecuteJavaScriptInIsolatedWorld(base::UTF8ToUTF16(script),
        base::BindOnce([](base::WeakPtr<content::WebContents> contents, content::GlobalRenderFrameHostId id,
                          base::Value value) {
          if (!contents || !value.is_string()) return;
          PollContentMessages(contents.get(), id, value.GetString());
        }, weak, id), crest::kContentWorldID);
  }
  static void PollContentMessages(content::WebContents* contents, content::GlobalRenderFrameHostId id,
                                  const std::string& doc) {
    auto* frame = content::RenderFrameHost::FromID(id);
    if (!frame || !frame->IsRenderFrameLive() || State().disposing ||
        content::WebContents::FromRenderFrameHost(frame) != contents) return;
    auto weak = contents->GetWeakPtr();
    frame->ExecuteJavaScriptInIsolatedWorld(u"globalThis.__crestBridge?.next()",
        base::BindOnce([](base::WeakPtr<content::WebContents> contents, content::GlobalRenderFrameHostId id,
                          std::string doc, base::Value value) {
          // An empty answer means the document went away or its world was
          // torn down; the next document arms a poll of its own.
          if (!contents || State().disposing || !value.is_dict()) return;
          const auto* batch_doc = value.GetDict().FindString("doc");
          const auto* messages = value.GetDict().FindList("messages");
          if (!batch_doc || *batch_doc != doc || !messages) return;
          auto* frame = content::RenderFrameHost::FromID(id);
          Page* page = nullptr;
          for (auto& [key, candidate] : State().pages)
            if (candidate->web_contents() == contents.get()) { page = candidate.get(); break; }
          if (!frame || !page) return;
          const url::Origin origin = frame->GetLastCommittedOrigin();
          const std::string identifier = ContentFrameIdentifier(frame, doc);
          for (const auto& message : *messages) {
            if (!message.is_dict()) continue;
            const auto* handler = message.GetDict().FindString("handler");
            const auto* body = message.GetDict().Find("body");
            auto json = body ? base::WriteJson(*body) : std::nullopt;
            if (!handler || !json) continue;
            page->observation(@"content_message", @{
              @"handler": base::SysUTF8ToNSString(*handler),
              @"body": base::SysUTF8ToNSString(*json),
              @"frame": base::SysUTF8ToNSString(identifier),
              @"isMainFrame": @(frame->IsInPrimaryMainFrame()),
              @"protocol": base::SysUTF8ToNSString(origin.scheme()),
              @"host": base::SysUTF8ToNSString(origin.host()),
              @"port": @(origin.port()) });
          }
          PollContentMessages(contents.get(), id, doc);
        }, weak, id, doc), crest::kContentWorldID);
  }
  void Publish(bool committed = false, NSString* failure = nil, int error_code = 0) {
    if (!web_contents() || State().disposing) return;
    auto& controller = web_contents()->GetController();
    observation(@"changed", @{
      @"url": base::SysUTF8ToNSString(web_contents()->GetVisibleURL().spec()),
      @"title": base::SysUTF16ToNSString(web_contents()->GetTitle()),
      @"isLoading": @(web_contents()->IsLoading()),
      @"canGoBack": @(controller.CanGoBack()), @"canGoForward": @(controller.CanGoForward()),
      @"backHistory": History(-1), @"forwardHistory": History(1),
      @"committed": @(committed), @"failure": failure ?: (id)NSNull.null, @"errorCode": @(error_code),
      @"secure": @(IsSecure()) });
  }
  // The engine's own verdict: a secure transport with no mixed content and no
  // certificate problem. Anything less is not reported as secure.
  bool IsSecure() {
    auto* helper = web_contents() ? SecurityStateTabHelper::FromWebContents(web_contents()) : nullptr;
    if (!helper) return false;
    const auto level = helper->GetSecurityLevel();
    return level == security_state::SECURE;
  }
  // Chrome Web Store support. Regular profiles only: a private window must
  // not change a Space's persistent extension state, so its store pages keep
  // the engine's own behavior.
  content::RenderFrameHost* StoreFrame() {
    if (!web_contents() || State().disposing) return nullptr;
    if (web_contents()->GetBrowserContext()->IsOffTheRecord()) return nullptr;
    auto* frame = web_contents()->GetPrimaryMainFrame();
    if (!frame || !IsWebStoreURL(frame->GetLastCommittedURL())) return nullptr;
    return frame;
  }
  void RunInStore(const std::string& script) {
    if (auto* frame = StoreFrame())
      frame->ExecuteJavaScriptInIsolatedWorld(base::UTF8ToUTF16(script), {},
                                             ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  void InjectStoreScript() {
    if (!StoreFrame()) return;
    RunInStore(CrestStoreScript());
    PublishStoreState();
  }
  void PublishStoreState() {
    auto* frame = StoreFrame();
    if (!frame) return;
    const std::string id = WebStoreExtensionID(frame->GetLastCommittedURL());
    bool installed = false;
    if (!id.empty()) {
      auto* profile = Profile::FromBrowserContext(web_contents()->GetBrowserContext());
      auto* registry = profile ? extensions::ExtensionRegistry::Get(profile) : nullptr;
      installed = registry && registry->GetInstalledExtension(id) != nullptr;
    }
    auto state = base::DictValue().Set("id", id).Set("installed", installed);
    auto json = base::WriteJson(state);
    if (!json) return;
    RunInStore("window.__crestStore && window.__crestStore.apply(" + *json + ");");
  }
  // A request the injected script wrote into the listing's own URL fragment.
  // The extension it names has to be the one the page is showing, so a store
  // page cannot ask Crest to install anything else, and the core still runs
  // its own install review before Chromium verifies the package.
  bool ConsumeStoreRequest(const GURL& url) {
    if (!StoreFrame() || !url.has_ref()) return false;
    const std::string_view ref = url.ref();
    NSString* event = nil;
    std::string requested;
    if (base::StartsWith(ref, "crest-install=")) {
      event = @"store_install";
      requested = std::string(ref.substr(std::string_view("crest-install=").size()));
    } else if (base::StartsWith(ref, "crest-remove=")) {
      event = @"store_remove";
      requested = std::string(ref.substr(std::string_view("crest-remove=").size()));
    } else {
      return false;
    }
    // Leave the listing's own address in place; the fragment is a message.
    RunInStore("history.replaceState(history.state, '', location.pathname + location.search);");
    const std::string expected = WebStoreExtensionID(url);
    if (expected.empty() || requested != expected) {
      PublishStoreState();
      return true;
    }
    // The core owns the request now: leave the button's own progress label in
    // place until the review it presents finishes.
    store_request_open = true;
    observation(event, @{ @"id": base::SysUTF8ToNSString(expected) });
    return true;
  }
  NSArray* History(int direction) {
    auto& controller = web_contents()->GetController();
    NSMutableArray* result = [NSMutableArray array];
    const int current = controller.GetCurrentEntryIndex();
    for (int depth = 1; depth <= 50; ++depth) {
      const int index = current + direction * depth;
      if (index < 0 || index >= controller.GetEntryCount()) break;
      auto* entry = controller.GetEntryAtIndex(index);
      if (!entry) break;
      [result addObject:@{ @"depth": @(depth),
        @"title": base::SysUTF16ToNSString(entry->GetTitle()),
        @"url": base::SysUTF8ToNSString(entry->GetVirtualURL().spec()) }];
    }
    return result;
  }
  void DidStartLoading() override { Publish(); }
  void DidStopLoading() override {
    Publish();
    if (web_contents())
      if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents())) PublishFavicon(driver->GetFavicon());
  }
  void TitleWasSet(content::NavigationEntry*) override { Publish(); }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
      ++navigation_generation;
      observation(@"navigation_started", @{});
    }
  }
  // Typing, clicking and scrolling in the page, at most once a second, so a
  // Quick Window's idle timer sees the person working in it.
  base::TimeTicks last_user_activity;
  void DidGetUserInteraction(const blink::WebInputEvent&) override {
    const auto now = base::TimeTicks::Now();
    if (!last_user_activity.is_null() && now - last_user_activity < base::Seconds(1)) return;
    last_user_activity = now;
    if (!State().disposing) observation(@"user_activity", @{});
  }
  void PrimaryMainDocumentElementAvailable() override {
    InjectStoreScript();
    if (web_contents()) InjectContentScripts(web_contents()->GetPrimaryMainFrame());
  }
  // The main frame is injected as soon as its document element exists; frames
  // below it once their document is parsed. The world guards itself against a
  // second installation in the same document.
  void DOMContentLoaded(content::RenderFrameHost* frame) override {
    if (frame && !frame->IsInPrimaryMainFrame()) InjectContentScripts(frame);
  }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    // A store listing's own fragment carries the install request the injected
    // script made. It is Crest's message, not a page the core should publish.
    if (navigation->IsInPrimaryMainFrame() && navigation->HasCommitted() &&
        navigation->IsSameDocument() && ConsumeStoreRequest(navigation->GetURL()))
      return;
    if (navigation->IsInPrimaryMainFrame() && navigation->HasCommitted()) ++navigation_revision;
    // Crest issues a new Media Session identity for the next document.
    if (navigation->IsInPrimaryMainFrame() && navigation->HasCommitted() && !navigation->IsSameDocument()) {
      media_document.clear();
      media_seen_active = false;
      media_last_playing = false;
    }
    // The store is a single-page application: a listing change keeps the
    // document, so the script stays and only its state has to be refreshed.
    if (navigation->IsInPrimaryMainFrame() && navigation->HasCommitted() &&
        navigation->IsSameDocument()) {
      // Restoring the listing's own address is Crest's own edit, not a change
      // of listing, so it must not reset a request that is still open.
      if (store_request_open) store_request_open = false;
      else PublishStoreState();
    }
    if (navigation->IsInPrimaryMainFrame()) {
      // A certificate error commits the engine's own interstitial, which
      // explains the problem and offers to proceed. It is shown as the page
      // rather than covered by Crest's failure view.
      const bool certificate_error = navigation->IsErrorPage() &&
          net::IsCertificateError(navigation->GetNetErrorCode());
      const bool failed = navigation->IsErrorPage() && !certificate_error;
      Publish(navigation->HasCommitted() && !failed, failed ? @"navigation_failed" : nil,
              failed ? navigation->GetNetErrorCode() : 0);
    }
  }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    Publish(false, @"process_terminated");
  }
  // Mixed content found after load, or a certificate decision, changes what
  // the address shows.
  void DidChangeVisibleSecurityState() override { Publish(); }
  void BeforeUnloadDialogCancelled() override {
    if (!closing || State().disposing) return;
    closing = false;
    observation(@"close_canceled", @{});
  }
  void BeforeUnloadFired(bool proceed) override {
    if (!proceed) BeforeUnloadDialogCancelled();
  }
  void WebContentsDestroyed() override {
    RemoveFaviconObservation();
    if (State().close_preflight) {
      const auto generation = State().close_generation;
      dispatch_async(dispatch_get_main_queue(), ^{ AdvancePageClosePreparation(generation, false); });
    }
    extension_popup.reset();
    side_panel.reset();
    devtools.reset();
    Observe(nullptr);
    if (!State().disposing) observation(@"closed", @{});
  }
};

void RefreshStoreButtons() {
  if (State().disposing) return;
  for (const auto& [id, page] : State().pages) page->PublishStoreState();
}

void OfferNativePage(base::WeakPtr<content::WebContents> contents, bool foreground);

// The Crest page that owns `contents`, or an empty string when no page does:
// a panel document, a popup or an engine tab that was never adopted.
std::string PageIdentifierForContents(content::WebContents* contents) {
  if (!contents) return std::string();
  for (const auto& [id, page] : State().pages) {
    if (page->web_contents() == contents) return id;
  }
  return std::string();
}

void RetractSidePanels(Profile* profile, const std::string& extension_id,
                       std::optional<int> tab_id) {
  if (!profile) return;
  for (const auto& [id, page] : State().pages) {
    if (!page->side_panel || page->side_panel->extension_id() != extension_id) continue;
    auto* contents = page->web_contents();
    if (!contents || !page->browser) continue;
    // A private window's pages run in the off-the-record profile, while the
    // registry and panel options belong to the profile it was derived from.
    if (page->browser->GetProfile()->GetOriginalProfile() != profile->GetOriginalProfile()) continue;
    if (tab_id && sessions::SessionTabHelper::IdForTab(contents).id() != *tab_id) continue;
    page->side_panel->Retract();
    page->side_panel.reset();
  }
}

struct BrowserOwner final : TabStripModelObserver {
  BrowserOwner(Browser* value, std::string native_window)
      : browser(value), window(std::move(native_window)), strip(value->tab_strip_model()) {
    strip->AddObserver(this);
  }
  ~BrowserOwner() override { if (strip) strip->RemoveObserver(this); }
  Browser* browser;
  std::string window;
  TabStripModel* strip;
  // Set only for a Browser the engine created for itself. `space` names the
  // Crest Space that reserved `window`; the window itself is opened lazily,
  // when the first tab that cannot join an opener is offered.
  std::string space;
  bool engine_window = false;
  bool presented = false;
  bool focused = true;
  void OnTabStripModelChanged(TabStripModel*, const TabStripModelChange& change,
                             const TabStripSelectionChange& selection) override {
    if (change.type() != TabStripModelChange::kInserted || State().disposing) return;
    for (const auto& inserted : change.GetInsert()->contents) {
      auto weak = inserted.contents->GetWeakPtr();
      const bool foreground = selection.new_contents == inserted.contents;
      // Core-created pages are registered before this next UI-thread turn.
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
  BrowserOwner* host = nullptr;
  for (const auto& [id, owner] : state.browsers)
    if (owner->strip && owner->strip->GetIndexOfWebContents(contents.get()) >= 0) { host = owner.get(); break; }
  // A window the engine created for itself (chrome.windows.create, an
  // extension app window) has no Crest window until one of its tabs needs it.
  // A renderer popup keeps its opener's window instead: that tab is adopted
  // beside the page that opened it, exactly as it was before this path existed.
  if (host && host->engine_window && !host->presented && source_id == NSNull.null) {
    host->presented = true;
    [NSClassFromString(@"CrestRoot") presentEngineWindow:base::SysUTF8ToNSString(host->window)
                                                  space:base::SysUTF8ToNSString(host->space)
                                                focused:host->focused ? YES : NO];
  }
  state.browser_observation(@{
    @"adoptionId": base::SysUTF8ToNSString(token), @"profileId": base::SysUTF8ToNSString(profile_id),
    @"windowId": host ? base::SysUTF8ToNSString(host->window) : (id)NSNull.null,
    @"spaceId": host && !host->space.empty() ? base::SysUTF8ToNSString(host->space) : (id)NSNull.null,
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
  // Named before the status check as well as the creation: a window the core is
  // opening for itself is never subject to `CanCreateEngineBrowser`.
  state.creating_window = window_id;
  if (Browser::GetCreationStatusForProfile(profile) != BrowserWindowInterface::CreationStatus::kOk) {
    state.creating_window.clear();
    return nullptr;
  }
  Browser* browser = Browser::Create(Browser::CreateParams(profile, false));
  state.creating_window.clear();
  state.browsers.emplace(key, std::make_unique<BrowserOwner>(browser, window_id));
  return browser;
}

// Reserves the Crest window that will host a Browser the engine created for
// itself, so `WindowForBrowser` resolves and its tabs can be offered with a
// window the core recognizes. The window is opened only once a tab needs it.
// A profile with no Space to host it is declined rather than routed into an
// unrelated Space; an off-the-record profile belongs to the private window
// composition and is declined when that window is closed.
bool RegisterEngineBrowser(Browser* browser) {
  auto& state = State();
  std::string profile_id;
  for (const auto& [id, profile] : state.profiles)
    if (profile == browser->GetProfile()) { profile_id = id; break; }
  if (profile_id.empty() || state.deleting_profiles.contains(profile_id)) return false;
  NSDictionary<NSString*, NSString*>* placement = [NSClassFromString(@"CrestRoot")
      reserveEngineWindowForProfile:base::SysUTF8ToNSString(profile_id)];
  NSString* window = placement[@"windowId"];
  NSString* space = placement[@"spaceId"];
  if (!window.length || !space.length) return false;
  const std::string key = profile_id + "/" + base::SysNSStringToUTF8(window);
  if (state.browsers.contains(key)) return false;
  auto owner = std::make_unique<BrowserOwner>(browser, base::SysNSStringToUTF8(window));
  owner->space = base::SysNSStringToUTF8(space);
  owner->engine_window = true;
  state.browsers.emplace(key, std::move(owner));
  return true;
}

download::DownloadItem* FindDownload(NSString* profile_id, NSString* guid) {
  if (State().disposing) return nullptr;
  auto found = State().profiles.find(base::SysNSStringToUTF8(profile_id));
  return found == State().profiles.end() ? nullptr :
      found->second->GetDownloadManager()->GetDownloadByGuid(base::SysNSStringToUTF8(guid));
}

NSString* DownloadWarningToken(download::DownloadItem* item) {
  return [NSString stringWithFormat:@"%d:%d", item->GetDangerType(), item->GetInsecureDownloadStatus()];
}

// Only warnings with an explicit user override enter the approval path. Policy
// blocks and known malware remain blocked; pending scans remain engine-owned.
NSString* DownloadWarning(download::DownloadItem* item, bool* blocked) {
  *blocked = false;
  if (item->IsInsecure()) {
    *blocked = item->GetInsecureDownloadStatus() != download::DownloadItem::WARN;
    return *blocked ? @"The engine blocked this insecure download." :
        @"This file was transferred over an insecure connection and could have been changed by someone else. Keep it only if you trust its source.";
  }
  if (!item->IsDangerous()) return nil;
  switch (item->GetDangerType()) {
    case download::DOWNLOAD_DANGER_TYPE_DANGEROUS_FILE:
      return @"This type of file can change your computer. Keep it only if you trust its source.";
    case download::DOWNLOAD_DANGER_TYPE_UNCOMMON_CONTENT:
      return @"This file is not commonly downloaded. The engine could not confirm that it is safe.";
    case download::DOWNLOAD_DANGER_TYPE_POTENTIALLY_UNWANTED:
      return @"This file may change your browser or computer settings without your permission.";
    case download::DOWNLOAD_DANGER_TYPE_ASYNC_SCANNING:
    case download::DOWNLOAD_DANGER_TYPE_ASYNC_LOCAL_PASSWORD_SCANNING:
    case download::DOWNLOAD_DANGER_TYPE_MAYBE_DANGEROUS_CONTENT:
      return nil;
    default:
      *blocked = true;
      return @"The engine blocked this download because of its safety or organization policy verdict.";
  }
}

NSMutableDictionary<NSString*, id>* DownloadValues(download::DownloadItem* item) {
  std::string profile_id;
  for (const auto& [id, profile] : State().profiles)
    if (profile == content::DownloadItemUtils::GetBrowserContext(item)) { profile_id = id; break; }
  if (profile_id.empty()) return nil;
  auto* contents = content::DownloadItemUtils::GetWebContents(item);
  id source = NSNull.null;
  for (const auto& [id, page] : State().pages)
    if (contents && page->web_contents() == contents) { source = base::SysUTF8ToNSString(id); break; }
  NSString* state = @"preparing";
  NSString* message = @"";
  switch (item->GetState()) {
    case download::DownloadItem::COMPLETE: state = @"finished"; break;
    case download::DownloadItem::CANCELLED: state = @"canceled"; break;
    case download::DownloadItem::INTERRUPTED:
      state = @"failed";
      message = base::SysUTF16ToNSString(DownloadItemModel(item).GetInterruptDescription());
      break;
    case download::DownloadItem::IN_PROGRESS:
      state = item->GetTargetFilePath().empty() ? @"preparing" : @"downloading";
      bool blocked;
      if (NSString* warning = DownloadWarning(item, &blocked)) {
        state = blocked ? @"failed" : @"warning";
        message = warning;
      }
      break;
    default: break;
  }
  return [@{
    @"downloadId": base::SysUTF8ToNSString(item->GetGuid()),
    @"profileId": base::SysUTF8ToNSString(profile_id), @"sourcePageId": source,
    @"filename": base::SysUTF8ToNSString(item->GetFileNameToReportUser().AsUTF8Unsafe()),
    @"path": base::SysUTF8ToNSString(item->GetTargetFilePath().AsUTF8Unsafe()),
    @"received": @(item->GetReceivedBytes()), @"total": @(item->GetTotalBytes()),
    @"startedAt": @(item->GetStartTime().InSecondsFSinceUnixEpoch()),
    @"restored": @(item->GetStartTime() < State().started_at),
    @"paused": @(item->IsPaused()), @"state": state, @"message": message,
    @"warningToken": DownloadWarningToken(item) } mutableCopy];
}
// A batch retains all WebContents until the native semantic operation accepts it.
// In particular, approving the first tab never destroys it if a later tab vetoes.
void FinishPageClosePreparation(uint64_t generation, bool allowed) {
  dispatch_async(dispatch_get_main_queue(), ^{
    auto& state = State();
    if (state.close_generation != generation || !state.close_preflight) return;
    bool current = allowed && !state.disposing;
    for (const auto& [id, revision] : state.close_revisions) {
      auto found = state.pages.find(id);
      if (found == state.pages.end() || !found->second->web_contents() ||
          found->second->navigation_revision != revision) current = false;
    }
    for (const auto& [id, page] : state.pages) {
      for (const auto& [key, owner] : state.browsers) {
        if (owner->browser == page->browser && state.close_windows.contains(owner->window) &&
            !state.close_revisions.contains(id)) current = false;
      }
    }
    auto completion = state.close_preflight;
    state.close_preflight = nil;
    state.close_pages.clear(); state.close_revisions.clear(); state.close_windows.clear();
    state.close_pending.clear(); state.close_index = 0;
    completion(current);
  });
}
void AdvancePageClosePreparation(uint64_t generation, bool allowed) {
  auto& state = State();
  if (state.close_generation != generation || !state.close_preflight) return;
  if (!allowed || state.disposing) { FinishPageClosePreparation(generation, false); return; }
  while (state.close_index < state.close_pages.size()) {
    const std::string id = state.close_pages[state.close_index++];
    auto found = state.pages.find(id);
    if (found == state.pages.end() || !found->second->web_contents()) {
      FinishPageClosePreparation(generation, false); return;
    }
    auto* contents = found->second->web_contents();
    if (!contents->NeedToFireBeforeUnloadOrUnloadEvents()) continue;
    state.close_pending = id;
    contents->DispatchBeforeUnload(false);
    return;
  }
  FinishPageClosePreparation(generation, true);
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
// The extension, only if it has a side panel entry for this page's own tab.
// Crest resolves the panel itself: `SidePanelService::OpenSidePanelForTab`
// drives Chrome's Views side-panel UI, which this build never creates.
const extensions::Extension* SidePanelExtension(NSString* extension_id, Page* page) {
  if (!page || !page->web_contents()) return nullptr;
  Profile* profile = page->browser->GetProfile();
  const auto id = base::SysNSStringToUTF8(extension_id);
  const auto* extension = extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(id);
  if (!extension || (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(id, profile))) return nullptr;
  auto* service = extensions::SidePanelService::Get(profile);
  if (!service) return nullptr;
  const int tab = sessions::SessionTabHelper::IdForTab(page->web_contents()).id();
  return service->HasSidePanelActionForTab(*extension, tab) ? extension : nullptr;
}
// chrome.commands. Crest owns the key-equivalent path, so an event the core
// did not claim is matched against the extension keybindings itself rather
// than through Chrome's Views keybinding registry, which this build never
// creates. Modelled on `ExtensionKeybindingRegistry`: the same command
// service, the same active-tab grant, and the same `commands.onCommand`
// payload, without the accelerator table a Views window would maintain.
ui::Accelerator ShortcutAccelerator(NSEvent* event) {
  const ui::KeyboardCode key = ui::KeyboardCodeFromNSEvent(event);
  if (key == ui::VKEY_UNKNOWN) return ui::Accelerator();
  return ui::Accelerator(key, ui::EventFlagsFromModifiers(event.modifierFlags));
}
// Delivers a named command to its extension, granting the active-tab
// permission first so the extension can act on the page it was invoked over.
void DeliverExtensionCommand(Profile* profile, const extensions::Extension& extension,
                             const std::string& command, content::WebContents* contents) {
  base::ListValue args;
  args.Append(command);
  base::Value tab;
  if (contents) {
    if (auto* granter = extensions::ActiveTabPermissionGranter::FromWebContents(contents))
      granter->GrantIfRequested(&extension);
    // The action APIs are privileged extension contexts by construction.
    const auto scrub = extensions::ExtensionTabUtil::GetScrubTabBehavior(
        &extension, extensions::mojom::ContextType::kPrivilegedExtension, contents);
    tab = base::Value(extensions::ExtensionTabUtil::CreateTabObject(contents, scrub, &extension).ToValue());
  }
  args.Append(std::move(tab));
  auto event = std::make_unique<extensions::Event>(
      extensions::events::COMMANDS_ON_COMMAND, "commands.onCommand", std::move(args), profile);
  event->user_gesture = extensions::EventRouter::UserGestureState::kEnabled;
  extensions::EventRouter::Get(profile)->DispatchEventToExtension(extension.id(), std::move(event));
}
}  // namespace

@interface CrestChromiumHost : NSObject <CrestChromiumEngineHost>
@end

@implementation CrestChromiumHost
- (void)setBrowserObserver:(void (^)(NSDictionary<NSString*, id>*))observer {
  CHECK(NSThread.isMainThread);
  State().browser_observation = [observer copy];
}
- (void)setDownloadObserver:(void (^)(NSDictionary<NSString*, id>*))observer {
  State().download_observation = [observer copy];
}
- (void)setDownloadDestinationResolver:(void (^)(NSDictionary<NSString*, id>*, void (^)(NSString*)))resolver {
  State().download_destination = [resolver copy];
}
- (void)cancelDownload:(NSString*)downloadID profile:(NSString*)profileID {
  // Do not mutate an item from inside its own notification stack.
  dispatch_async(dispatch_get_main_queue(), ^{
    if (auto* item = FindDownload(profileID, downloadID)) item->Cancel(true);
  });
}
- (void)approveDownload:(NSString*)downloadID profile:(NSString*)profileID warning:(NSString*)token {
  auto* item = FindDownload(profileID, downloadID);
  if (!item || item->GetState() != download::DownloadItem::IN_PROGRESS ||
      ![DownloadWarningToken(item) isEqualToString:token]) return;
  bool blocked;
  if (!DownloadWarning(item, &blocked) || blocked) return;
  if (item->IsInsecure()) item->ValidateInsecureDownload();
  else if (item->IsDangerous()) item->ValidateDangerousDownload();
}
- (void)removeDownload:(NSString*)downloadID profile:(NSString*)profileID {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (auto* item = FindDownload(profileID, downloadID)) item->Remove();
  });
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
  state.pages.emplace(key, std::move(page)); state.adoptions.erase(found);
  observer(@"created", @{});
  if (Page* adopted = FindPage(pageID)) adopted->Publish();
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
  const std::string profile_id = base::SysNSStringToUTF8(profileID);
  if (!base::Uuid::ParseCaseInsensitive(profile_id).is_valid() || state.deleting_profiles.contains(profile_id)) return NO;
  state.creating_pages.emplace(key, profile_id);
  auto* manager = g_browser_process->profile_manager();
  CHECK(manager);
  if (privateMode && !sourceProfileID.length) { state.creating_pages.erase(key); return NO; }
  const std::string source_id = privateMode ? base::SysNSStringToUTF8(sourceProfileID) : profile_id;
  if (!base::Uuid::ParseCaseInsensitive(source_id).is_valid() || state.deleting_profiles.contains(source_id)) {
    state.creating_pages.erase(key); return NO;
  }
  const base::FilePath path = manager->user_data_dir().AppendASCII("Crest-" + source_id);
  manager->CreateProfileAsync(path, base::BindOnce(
      [](std::string page_id, std::string profile_id, std::string source_id, std::string window_id,
         bool private_mode, Observation observer, Profile* profile) {
        auto& state = State();
        if (!state.creating_pages.erase(page_id)) return;
        if (!profile || state.disposing || state.deleting_profiles.contains(profile_id) || state.deleting_profiles.contains(source_id)) {
          observer(@"creation_failed", @{}); return;
        }
        if (!state.profiles.contains(profile_id)) {
          // The regular source owns the OTR profile and must outlive it. No
          // private profile path, session checkpoint, or browsing history is created.
          state.profile_leases[profile_id] = std::make_unique<ScopedProfileKeepAlive>(
              profile, ProfileKeepAliveOrigin::kAppWindow);
          state.profiles[profile_id] = private_mode ? profile->GetOffTheRecordProfile(
              Profile::OTRProfileID::CreateUnique("Crest::Private::" + profile_id), true) : profile;
        }
        Browser* browser = BrowserFor(profile_id, window_id);
        if (!browser) { observer(@"creation_failed", @{}); return; }
        // Keep the controller's initial entry until the adapter supplies its
        // first URL or restored history. Navigating to about:blank here races
        // restoration and can leave a spurious Back entry in ordinary tabs.
        content::WebContents::CreateParams params(state.profiles[profile_id]);
        params.initially_hidden = true;
        params.desired_renderer_state = content::WebContents::CreateParams::kNoRendererProcess;
        auto owned_contents = content::WebContents::Create(params);
        auto* contents = owned_contents.get();
        browser->tab_strip_model()->AddWebContents(std::move(owned_contents), -1,
            ui::PAGE_TRANSITION_AUTO_TOPLEVEL, AddTabTypes::ADD_NONE);
        state.pages.emplace(page_id, std::make_unique<Page>(contents, browser, profile_id, observer));
        observer(@"created", @{});
      }, key, profile_id, source_id, base::SysNSStringToUTF8(windowID), static_cast<bool>(privateMode), [observer copy]));
  return YES;
}
- (NSView*)viewForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  return page && page->web_contents() ? page->web_contents()->GetNativeView().GetNativeNSView() : nil;
}
- (void)setLinkHandlerForPage:(NSString*)pageID handler:(BOOL (^)(NSString*, NSString*, NSString*))handler {
  CHECK(NSThread.isMainThread);
  if (Page* page = FindPage(pageID)) page->link_handler = [handler copy];
}
- (void)setProtectedLinkHandlerForPage:(NSString*)pageID handler:(CrestDeferredNavigation (^)(NSString*))handler {
  CHECK(NSThread.isMainThread);
  if (Page* page = FindPage(pageID)) page->protected_link_handler = [handler copy];
}
- (void)setModifiedLinkHandlerForPage:(NSString*)pageID
    handler:(void (^)(NSString*, NSUInteger, NSString*, void (^)(NSString*, CrestDeferredNavigation)))handler {
  CHECK(NSThread.isMainThread);
  if (Page* page = FindPage(pageID)) page->modified_link_handler = [handler copy];
}
- (void)discardPendingNavigation:(NSString*)token {
  CHECK(NSThread.isMainThread);
  State().pending_link_navigations.erase(base::SysNSStringToUTF8(token));
}
- (BOOL)loadPendingNavigation:(NSString*)token page:(NSString*)pageID expectedURL:(NSString*)url {
  CHECK(NSThread.isMainThread);
  auto& pending = State().pending_link_navigations;
  auto found = pending.find(base::SysNSStringToUTF8(token));
  if (found == pending.end()) return NO;
  auto navigation = std::move(found->second);
  pending.erase(found);  // Tokens can be consumed only once, including failures.
  Page* page = FindPage(pageID);
  if (State().disposing || !page || page->closing || !page->web_contents() || !navigation.source ||
      page->profile != navigation.profile || navigation.request.url != GURL(base::SysNSStringToUTF8(url)) ||
      !page->web_contents()->GetController().IsInitialNavigation()) return NO;
  bool current_source = false;
  for (const auto& [id, source] : State().pages) {
    if (source->web_contents() == navigation.source.get() && source->browser == page->browser &&
        !source->closing && source->navigation_revision == navigation.revision &&
        source->navigation_generation == navigation.generation) { current_source = true; break; }
  }
  if (!current_source) return NO;
  // Keep Chromium's verified referrer, initiator, headers and SiteInstance.
  content::NavigationController::LoadURLParams load(navigation.request);
  page->web_contents()->GetController().LoadURLWithParams(load);
  return YES;
}
- (NSData*)interactionStateForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents()) return nil;
  auto& controller = page->web_contents()->GetController();
  if (controller.IsInitialNavigation() || !controller.GetLastCommittedEntry() ||
      controller.GetEntryCount() > 100 || controller.GetLastCommittedEntryIndex() < 0) return nil;
  base::Pickle pickle;
  pickle.WriteString("crest.navigation.v1");
  pickle.WriteString(page->profile);
  pickle.WriteInt(controller.GetLastCommittedEntryIndex());
  pickle.WriteInt(controller.GetEntryCount());
  for (int i = 0; i < controller.GetEntryCount(); ++i) {
    auto navigation = sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(i, controller.GetEntryAtIndex(i));
    base::Pickle entry;
    // Chromium's session serializer sanitizes password data before writing.
    navigation.WriteToPickle(64 * 1024, &entry);
    pickle.WriteData(entry.AsBytes());
    if (pickle.AsBytes().size() > 2 * 1024 * 1024) return nil;
  }
  return [NSData dataWithBytes:pickle.AsBytes().data() length:pickle.AsBytes().size()];
}
- (BOOL)restorePage:(NSString*)pageID interactionState:(NSData*)data expectedURL:(NSString*)url {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents() || !data.length || data.length > 2 * 1024 * 1024) return NO;
  auto& controller = page->web_contents()->GetController();
  // Restoration is only for a new native page, never a replacement of live work.
  if (!controller.IsInitialNavigation()) return NO;
  auto iterator = base::PickleIterator::WithData(base::apple::NSDataToSpan(data));
  std::string magic, profile;
  int selected, count;
  if (!iterator.ReadString(&magic) || magic != "crest.navigation.v1" ||
      !iterator.ReadString(&profile) || profile != page->profile ||
      !iterator.ReadInt(&selected) || !iterator.ReadInt(&count) || count < 1 || count > 100 ||
      selected < 0 || selected >= count) return NO;
  std::vector<sessions::SerializedNavigationEntry> saved;
  for (int i = 0; i < count; ++i) {
    auto bytes = iterator.ReadData();
    if (!bytes || bytes->size() > 68 * 1024) return NO;
    auto entry = base::PickleIterator::WithData(*bytes);
    sessions::SerializedNavigationEntry navigation;
    if (!navigation.ReadFromPickle(&entry) || !navigation.virtual_url().is_valid()) return NO;
    saved.push_back(std::move(navigation));
  }
  const GURL expected(base::SysNSStringToUTF8(url));
  if (!iterator.ReachedEnd() || !expected.is_valid() ||
      saved[selected].virtual_url().GetWithoutRef() != expected.GetWithoutRef()) return NO;
  auto entries = sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(saved, page->web_contents()->GetBrowserContext());
  if (entries.size() != saved.size() || std::any_of(entries.begin(), entries.end(), [](const auto& entry) { return !entry; })) return NO;
  page->web_contents()->Stop();
  controller.DiscardNonCommittedEntries();
  controller.Restore(selected, content::RestoreType::kRestored, &entries);
  controller.LoadIfNecessary();
  page->Publish();
  return YES;
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
  } else if ([command isEqualToString:@"engine.history"]) {
    const int offset = url.intValue;
    if (offset == 0 || !controller.CanGoToOffset(offset)) return NO;
    controller.GoToOffset(offset);
  } else if ([command isEqualToString:@"engine.reload"] ||
             [command isEqualToString:@"engine.reload_from_origin"]) {
    controller.Reload([command isEqualToString:@"engine.reload_from_origin"]
        ? content::ReloadType::BYPASSING_CACHE : content::ReloadType::NORMAL, true);
  } else if ([command isEqualToString:@"engine.stop"]) {
    contents->Stop();
  } else if ([command isEqualToString:@"engine.media_activate"]) {
    const std::string document = base::SysNSStringToUTF8(url ?: @"");
    if (document.empty() || document.size() > 128) return NO;
    page->media_document = document;
    page->PublishMediaSession();
  } else if ([command isEqualToString:@"engine.media_action"] ||
             [command isEqualToString:@"engine.media_mute"]) {
    // `url` carries "<action or 0/1>:<document>"; a stale document is ignored.
    const std::string value = base::SysNSStringToUTF8(url ?: @"");
    const auto separator = value.find(':');
    if (separator == std::string::npos || value.substr(separator + 1) != page->media_document) return NO;
    const std::string argument = value.substr(0, separator);
    if ([command isEqualToString:@"engine.media_mute"]) {
      contents->SetAudioMuted(argument == "1");
      return YES;
    }
    auto* media_session = content::MediaSession::Get(contents);
    if (!media_session) return NO;
    using SuspendType = media_session::mojom::MediaSession::SuspendType;
    if (argument == "play") media_session->Resume(SuspendType::kUI);
    else if (argument == "pause") media_session->Suspend(SuspendType::kUI);
    else if (argument == "previoustrack") media_session->PreviousTrack();
    else if (argument == "nexttrack") media_session->NextTrack();
    else return NO;
  } else if ([command isEqualToString:@"engine.infobar"]) {
    // `url` carries "<response>:<id>".
    auto parts = base::SplitString(base::SysNSStringToUTF8(url ?: @""), ":", base::KEEP_WHITESPACE, base::SPLIT_WANT_ALL);
    int id = 0;
    if (parts.size() != 2 || !base::StringToInt(parts[1], &id)) return NO;
    return page->RespondToInfoBar(id, parts[0]) ? YES : NO;
  } else if ([command isEqualToString:@"engine.show_blocked_popups"]) {
    auto* blocker = blocked_content::PopupBlockerTabHelper::FromWebContents(contents);
    if (!blocker || !blocker->GetBlockedPopupsCount()) return NO;
    blocker->ShowAllBlockedPopups();
    page->published_blocked_popups = 0;
  } else if ([command isEqualToString:@"engine.extensions"]) {
    if (page->browser->GetProfile()->IsOffTheRecord()) return NO;
    NavigateParams params(page->browser, GURL("chrome://extensions/"), ui::PAGE_TRANSITION_AUTO_TOPLEVEL);
    params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
    params.window_action = NavigateParams::WindowAction::kNoAction;
    Navigate(&params);
  } else if ([command isEqualToString:@"engine.inspect"] ||
             [command isEqualToString:@"engine.inspect_console"] ||
             [command isEqualToString:@"engine.inspect_elements"] ||
             [command isEqualToString:@"engine.inspect_network"]) {
    // DevToolsToggleAction is the only public way to choose a starting panel,
    // and it covers Console and Elements. Network has no toggle action, and the
    // frontend's panel parameter is private to DevToolsWindow, so a Network
    // request opens DevTools without selecting a panel; the engine reports that
    // back as an inspector opened on no known panel.
    DevToolsToggleAction action = DevToolsToggleAction::Show();
    DevToolsOpenedByAction opened_by = DevToolsOpenedByAction::kMainMenuOrMainShortcut;
    if ([command isEqualToString:@"engine.inspect_console"]) {
      action = DevToolsToggleAction::ShowConsolePanel();
      opened_by = DevToolsOpenedByAction::kConsoleShortcut;
    } else if ([command isEqualToString:@"engine.inspect_elements"]) {
      action = DevToolsToggleAction::ShowElementsPanel();
    }
    DevToolsWindow::OpenDevToolsWindow(contents, action, opened_by);
  } else if ([command isEqualToString:@"engine.inspect_visible"]) {
    // A state query: the answer is this command's result, not an action.
    return DevToolsWindow::GetInstanceForInspectedWebContents(contents) != nullptr;
  } else if ([command isEqualToString:@"engine.inspect_close"]) {
    auto* inspector = DevToolsWindow::GetInstanceForInspectedWebContents(contents);
    if (!inspector) return NO;
    // Closing the frontend contents is the one path that covers both states: a
    // docked frontend is its own delegate and tears the inspector down from
    // here, and an undocked one takes the same route its window close takes.
    // The browser-scoped toggle cannot be used instead — it acts on whichever
    // tab is active, which is not necessarily the card this command names.
    content::WebContents* frontend = inspector->GetDevToolsWebContents();
    if (!frontend) return NO;
    frontend->Close();
  } else if ([command isEqualToString:@"engine.zoom"]) {
    const double factor = url.doubleValue;
    auto* zoom = zoom::ZoomController::FromWebContents(contents);
    if (!zoom || !std::isfinite(factor) || factor < 0.25 || factor > 5) return NO;
    zoom->SetZoomMode(zoom::ZoomController::ZOOM_MODE_ISOLATED);
    zoom->SetZoomLevel(blink::ZoomFactorToZoomLevel(factor));
  } else if ([command isEqualToString:@"engine.store_state"]) {
    // The core finished or abandoned an install review; the listing's own
    // button goes back to the state Chromium's registry reports.
    page->store_request_open = false;
    page->PublishStoreState();
  } else if ([command isEqualToString:@"engine.close_page"]) {
    const int index = page->browser->tab_strip_model()->GetIndexOfWebContents(contents);
    if (index < 0 || page->closing) return NO;
    page->closing = true;
    page->browser->tab_strip_model()->CloseWebContentsAt(index, 0);
  } else { return NO; }
  return YES;
}
- (NSArray<NSData*>*)certificateChainForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents()) return @[];
  auto* entry = page->web_contents()->GetController().GetVisibleEntry();
  if (!entry || !entry->GetSSL().certificate) return @[];
  const auto& certificate = entry->GetSSL().certificate;
  NSMutableArray<NSData*>* chain = [NSMutableArray array];
  auto append = [&](const CRYPTO_BUFFER* buffer) {
    auto bytes = net::x509_util::CryptoBufferAsSpan(buffer);
    [chain addObject:[NSData dataWithBytes:bytes.data() length:bytes.size()]];
  };
  append(certificate->cert_buffer());
  for (const auto& intermediate : certificate->intermediate_buffers()) append(intermediate.get());
  return chain;
}
- (NSArray<NSDictionary<NSString*, id>*>*)permissionsForPage:(NSString*)pageID {
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents()) return @[];
  GURL origin = page->web_contents()->GetLastCommittedURL().DeprecatedGetOriginAsURL();
  if (!origin.SchemeIsHTTPOrHTTPS()) return @[];
  auto* settings = HostContentSettingsMapFactory::GetForProfile(page->browser->GetProfile());
  NSMutableArray* result = [NSMutableArray array];
  for (const auto& permission : kSitePermissions) {
    ContentSetting value = settings->GetContentSetting(origin, origin, permission.type);
    [result addObject:@{ @"id": base::SysUTF8ToNSString(permission.key), @"label": base::SysUTF8ToNSString(permission.label),
        @"value": @(value), @"supportsAsk": @(permission.supports_ask) }];
  }
  return result;
}
- (BOOL)setPermission:(NSString*)permissionID page:(NSString*)pageID value:(NSInteger)value {
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents()) return NO;
  GURL origin = page->web_contents()->GetLastCommittedURL().DeprecatedGetOriginAsURL();
  if (!origin.SchemeIsHTTPOrHTTPS()) return NO;
  for (const auto& permission : kSitePermissions) {
    if (base::SysNSStringToUTF8(permissionID) != permission.key) continue;
    // CONTENT_SETTING_DEFAULT clears the site's own setting.
    if (value != CONTENT_SETTING_DEFAULT && value != CONTENT_SETTING_ALLOW && value != CONTENT_SETTING_BLOCK &&
        !(permission.supports_ask && value == CONTENT_SETTING_ASK)) return NO;
    HostContentSettingsMapFactory::GetForProfile(page->browser->GetProfile())
        ->SetContentSettingDefaultScope(origin, GURL(), permission.type, static_cast<ContentSetting>(value));
    return YES;
  }
  return NO;
}
- (NSArray<NSDictionary<NSString*, id>*>*)extensionsForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents()) return @[];
  Profile* profile = page->browser->GetProfile();
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* actions = extensions::ExtensionActionManager::Get(profile);
  if (!registry || !actions) return @[];
  const int tab = sessions::SessionTabHelper::IdForTab(page->web_contents()).id();
  auto* observer = ExtensionStateObserver::Ensure(profile, page->profile);
  NSMutableArray* result = [NSMutableArray array];
  for (const auto& extension : registry->enabled_extensions()) {
    if (!extension->is_extension() || extensions::Manifest::IsComponentLocation(extension->location()) ||
        (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(extension->id(), profile))) continue;
    auto* action = actions->GetExtensionAction(*extension);
    if (!action) continue;
    // An extension whose files are gone has no action to offer.
    if (!observer->IsAvailable(*extension, action)) continue;
    auto* model = ToolbarActionsModel::Get(profile);
    NSImage* icon = observer->IconFor(*extension, action, tab);
    [result addObject:@{ @"id": base::SysUTF8ToNSString(extension->id()),
        @"name": base::SysUTF8ToNSString(extension->name()), @"icon": icon ?: (id)NSNull.null,
        @"pinned": @(model && model->IsActionPinned(extension->id())),
        @"badge": base::SysUTF8ToNSString(action->GetExplicitlySetBadgeText(tab)) }];
  }
  return result;
}
- (BOOL)runExtension:(NSString*)extensionID page:(NSString*)pageID
         anchorView:(NSView*)anchorView anchorRect:(NSRect)anchorRect {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents() || !anchorView.window ||
      anchorView.window != crest::WindowForBrowser(page->browser)) return NO;
  Profile* profile = page->browser->GetProfile();
  const auto id = base::SysNSStringToUTF8(extensionID);
  const auto* extension = extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(id);
  if (!extension || (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(id, profile))) return NO;
  // Declined rather than navigated: an extension whose files are gone would
  // otherwise show Chromium's own ERR_FILE_NOT_FOUND page inside Crest's
  // popup window. The core states this as an unavailable action instead.
  if (!ExtensionStateObserver::Ensure(profile, page->profile)->IsAvailable(*extension,
          extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(*extension))) return NO;
  auto* contents = page->web_contents();
  const int index = page->browser->tab_strip_model()->GetIndexOfWebContents(contents);
  if (index < 0) return NO;
  page->browser->tab_strip_model()->ActivateTabAt(index);
  auto* runner = extensions::ExtensionActionRunner::GetForWebContents(contents);
  if (!runner) return NO;
  // This path is invoked only by the user's native extension action button.
  const auto result = runner->RunAction(extension, true);
  if (result == extensions::ExtensionAction::ShowAction::kNone) return YES;
  if (result == extensions::ExtensionAction::ShowAction::kToggleSidePanel) {
    // The action opens a panel instead of a popup. The card belongs to the
    // core, so the click toggles the one this page is already showing.
    [NSClassFromString(@"CrestRoot") routeSidePanel:extensionID page:pageID
                                           request:CrestSidePanelRequestToggle];
    return YES;
  }
  if (result != extensions::ExtensionAction::ShowAction::kShowPopup) return NO;
  auto* action = extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(*extension);
  if (!action) return NO;
  auto popup = extensions::ExtensionViewHostFactory::CreatePopupHost(*extension,
      action->GetPopupUrl(sessions::SessionTabHelper::IdForTab(contents).id()), page->browser);
  if (!popup) return NO;
  page->extension_popup = std::make_unique<ExtensionPopup>(std::move(popup), anchorView, anchorRect);
  return YES;
}
- (NSArray<NSDictionary<NSString*, id>*>*)pinnedExtensionsForProfile:(NSString*)profileID {
  CHECK(NSThread.isMainThread);
  // The pinned strip belongs to the Space, not to whatever page happens to be
  // open in it: a Space showing its Start Page still has the extensions the
  // user pinned to it. The per-page list stays the source of per-tab state
  // (badge, dynamic icon, page-action enablement) and is overlaid on this.
  const auto profile_id = base::SysNSStringToUTF8(profileID);
  auto found = State().profiles.find(profile_id);
  if (found == State().profiles.end()) return @[];
  Profile* profile = found->second;
  // A private window reads the same Space's pinned list and narrows it to the
  // extensions that are allowed in incognito. The registry, the action manager
  // and the toolbar model all belong to the regular profile that owns it.
  const bool private_mode = profile->IsOffTheRecord();
  Profile* owner = profile->GetOriginalProfile();
  auto* registry = extensions::ExtensionRegistry::Get(owner);
  auto* actions = extensions::ExtensionActionManager::Get(owner);
  if (!registry || !actions) return @[];
  // The pinned list is read from the preference `ToolbarActionsModel` persists
  // rather than from the model itself. A Space whose engine profile was only
  // just loaded — which is every Space on a Start Page, before anything has
  // been opened in it — has no initialized model yet, and the row would stay
  // empty until something else happened to rebuild it.
  std::set<std::string> pinned;
  for (const base::Value& entry :
       owner->GetPrefs()->GetList(extensions::pref_names::kPinnedExtensions)) {
    if (const std::string* id = entry.GetIfString()) pinned.insert(*id);
  }
  if (pinned.empty()) return @[];
  auto* observer = ExtensionStateObserver::Ensure(profile, profile_id);
  const int tab = extensions::ExtensionAction::kDefaultTabId;
  NSMutableArray* result = [NSMutableArray array];
  for (const auto& extension : registry->enabled_extensions()) {
    if (!extension->is_extension() || extensions::Manifest::IsComponentLocation(extension->location())) continue;
    if (private_mode && !extensions::util::IsIncognitoEnabled(extension->id(), owner)) continue;
    if (!pinned.contains(extension->id())) continue;
    auto* action = actions->GetExtensionAction(*extension);
    if (!action || !observer->IsAvailable(*extension, action)) continue;
    // Page actions exist only in relation to a page. With none open the tile
    // is still shown — the user pinned it — but it has nothing to act on.
    const bool enabled = action->action_type() != extensions::ActionInfo::Type::kPage;
    NSImage* icon = observer->IconFor(*extension, action, tab);
    [result addObject:@{ @"id": base::SysUTF8ToNSString(extension->id()),
        @"name": base::SysUTF8ToNSString(extension->name()), @"icon": icon ?: (id)NSNull.null,
        @"pinned": @YES, @"enabled": @(enabled),
        @"badge": base::SysUTF8ToNSString(action->GetExplicitlySetBadgeText(tab)) }];
  }
  return result;
}
- (BOOL)runExtension:(NSString*)extensionID profile:(NSString*)profileID window:(NSString*)windowID
          anchorView:(NSView*)anchorView anchorRect:(NSRect)anchorRect {
  CHECK(NSThread.isMainThread);
  // The page-less click. There is no tab to activate, no host permission to
  // grant and nothing to inject, so only an action that carries its own popup
  // document can run: it is opened against the Space's Browser directly rather
  // than through the WebContents-scoped action runner.
  if (!anchorView.window) return NO;
  const auto profile_id = base::SysNSStringToUTF8(profileID);
  auto found = State().profiles.find(profile_id);
  if (found == State().profiles.end()) return NO;
  Profile* profile = found->second;
  Profile* owner = profile->GetOriginalProfile();
  const auto id = base::SysNSStringToUTF8(extensionID);
  const auto* extension = extensions::ExtensionRegistry::Get(owner)->enabled_extensions().GetByID(id);
  if (!extension) return NO;
  if (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(id, owner)) return NO;
  auto* action = extensions::ExtensionActionManager::Get(owner)->GetExtensionAction(*extension);
  if (!action || !ExtensionStateObserver::Ensure(profile, profile_id)->IsAvailable(*extension, action)) return NO;
  if (action->action_type() == extensions::ActionInfo::Type::kPage) return NO;
  const GURL popup_url = action->GetPopupUrl(extensions::ExtensionAction::kDefaultTabId);
  if (!popup_url.is_valid()) return NO;
  Browser* browser = BrowserFor(profile_id, base::SysNSStringToUTF8(windowID));
  if (!browser || anchorView.window != crest::WindowForBrowser(browser)) return NO;
  auto popup = extensions::ExtensionViewHostFactory::CreatePopupHost(*extension, popup_url, browser);
  if (!popup) return NO;
  State().space_extension_popup = std::make_unique<ExtensionPopup>(std::move(popup), anchorView, anchorRect);
  return YES;
}
- (BOOL)hasSidePanel:(NSString*)extensionID page:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  return SidePanelExtension(extensionID, FindPage(pageID)) != nullptr;
}
- (NSView*)openSidePanel:(NSString*)extensionID page:(NSString*)pageID closed:(void (^)(void))closed {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  const auto* extension = SidePanelExtension(extensionID, page);
  if (!extension) return nil;
  auto* service = extensions::SidePanelService::Get(page->browser->GetProfile());
  auto* contents = page->web_contents();
  auto options = service->GetOptions(*extension, sessions::SessionTabHelper::IdForTab(contents).id());
  if (!options.path || options.path->empty() || options.enabled == false) return nil;
  const GURL url = extension->ResolveExtensionURL(*options.path);
  if (!url.is_valid()) return nil;
  auto panel = extensions::ExtensionViewHostFactory::CreateSidePanelHost(*extension, url,
      page->browser, page->browser->tab_strip_model()->GetTabForWebContents(contents));
  if (!panel) return nil;
  page->side_panel = std::make_unique<ExtensionSidePanel>(std::move(panel), extension->id(), closed);
  return page->side_panel->container();
}
- (void)closeSidePanelForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page) return;
  page->side_panel.reset();
}
- (NSView*)devToolsViewForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  return page && page->devtools ? page->devtools->container() : nil;
}
- (NSDictionary<NSString*, NSValue*>*)layoutDevToolsForPage:(NSString*)pageID container:(NSRect)container {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->devtools || NSIsEmptyRect(container)) return nil;
  // The frontend takes the whole card interior and the inspected page is drawn
  // on top of it at the rectangle the frontend asked for, which is how its own
  // dock side, splitter position and drawer height reach the card.
  gfx::Rect frontend_bounds;
  gfx::Rect page_bounds;
  ApplyDevToolsContentsResizingStrategy(
      page->devtools->strategy,
      gfx::Rect(0, 0, static_cast<int>(NSWidth(container)), static_cast<int>(NSHeight(container))),
      &frontend_bounds, &page_bounds);
  // Chromium measures from the top left; AppKit measures from the bottom left.
  auto flipped = [&container](const gfx::Rect& rect) {
    return [NSValue valueWithRect:NSMakeRect(NSMinX(container) + rect.x(),
        NSMinY(container) + NSHeight(container) - rect.y() - rect.height(),
        rect.width(), rect.height())];
  };
  return @{ @"devTools": flipped(frontend_bounds), @"page": flipped(page_bounds) };
}
- (NSDictionary<NSString*, id>*)dispatchExtensionShortcut:(NSEvent*)event page:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents() || State().disposing) return nil;
  const ui::Accelerator accelerator = ShortcutAccelerator(event);
  if (accelerator.key_code() == ui::VKEY_UNKNOWN) return nil;
  Profile* profile = page->browser->GetProfile();
  auto* commands = extensions::CommandService::Get(profile);
  if (!commands) return nil;
  for (const auto& extension : extensions::ExtensionRegistry::Get(profile)->enabled_extensions()) {
    const auto& id = extension->id();
    if (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(id, profile)) continue;
    // `_execute_action` is the action itself, so the core runs it through the
    // same path as a click on the extension's own button.
    extensions::Command action;
    bool active = false;
    if (commands->GetExtensionActionCommand(id, extensions::ActionInfo::Type::kAction,
            extensions::CommandService::ACTIVE, &action, &active) &&
        active && action.accelerator() == accelerator) {
      return @{@"action": base::SysUTF8ToNSString(id)};
    }
    ui::CommandMap named;
    if (!commands->GetNamedCommands(id, extensions::CommandService::ACTIVE,
                                    extensions::CommandService::REGULAR, &named)) continue;
    for (const auto& [name, command] : named) {
      if (command.accelerator() != accelerator) continue;
      DeliverExtensionCommand(profile, *extension, name, page->web_contents());
      return @{@"handled": @YES};
    }
  }
  return nil;
}
- (NSString*)engineVersion { return base::SysUTF8ToNSString(version_info::GetVersionNumber()); }
- (void)setExtensionReview:(void (^)(NSDictionary<NSString*, id>*, NSWindow*, void (^)(BOOL, BOOL)))review {
  State().extension_review = [review copy];
}
- (void)prepareExtensionProfile:(NSString*)profileID completion:(void (^)(BOOL))completion {
  const auto id = base::SysNSStringToUTF8(profileID);
  if (!base::Uuid::ParseCaseInsensitive(id).is_valid() || State().disposing || State().deleting_profiles.contains(id)) { completion(NO); return; }
  if (State().profiles.contains(id)) { completion(!State().profiles[id]->IsOffTheRecord()); return; }
  auto* manager = g_browser_process->profile_manager();
  manager->CreateProfileAsync(manager->user_data_dir().AppendASCII("Crest-" + id), base::BindOnce(
    [](std::string id, void (^done)(BOOL), Profile* profile) {
      if (!profile || State().disposing || State().deleting_profiles.contains(id)) { done(NO); return; }
      if (!State().profiles.contains(id)) {
        State().profiles[id] = profile;
        State().profile_leases[id] = std::make_unique<ScopedProfileKeepAlive>(profile, ProfileKeepAliveOrigin::kAppWindow);
      }
      ExtensionStateObserver::Ensure(profile, id);
      done(YES);
    }, id, [completion copy]));
}
- (NSArray<NSDictionary<NSString*, id>*>*)extensionsForProfile:(NSString*)profileID {
  const auto profile_id = base::SysNSStringToUTF8(profileID);
  auto found = State().profiles.find(profile_id);
  if (found == State().profiles.end() || found->second->IsOffTheRecord()) return @[];
  auto* profile = found->second;
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* observer = ExtensionStateObserver::Ensure(profile, profile_id);
  NSMutableArray* result = [NSMutableArray array];
  for (const auto& extension : registry->GenerateInstalledExtensionsSet()) {
    if (!extension->is_extension() || extensions::Manifest::IsComponentLocation(extension->location())) continue;
    auto* action = extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(*extension);
    // An extension that still has a registry entry but no files on disk is
    // reported as absent, not as a row the user could act on.
    if (!observer->IsAvailable(*extension, action)) continue;
    NSMutableArray* warnings = [NSMutableArray array];
    for (const auto& permission : extension->permissions_data()->GetPermissionMessages())
      [warnings addObject:base::SysUTF16ToNSString(permission.message())];
    NSImage* icon = observer->IconFor(*extension, action, -1);
    [result addObject:@{@"id": base::SysUTF8ToNSString(extension->id()),
      @"name": base::SysUTF8ToNSString(extension->name()), @"version": base::SysUTF8ToNSString(extension->version().GetString()),
      @"description": base::SysUTF8ToNSString(extension->manifest()->FindStringPath("description") ? *extension->manifest()->FindStringPath("description") : std::string()), @"icon": icon ?: (id)NSNull.null,
      @"enabled": @(registry->enabled_extensions().Contains(extension->id())), @"permissions": warnings,
      @"webStore": @(extension->from_webstore()),
      @"options": base::SysUTF8ToNSString(extensions::OptionsPageInfo::GetOptionsPage(extension.get()).spec())}];
  }
  return result;
}
- (BOOL)extensionCommand:(NSString*)command extension:(NSString*)extensionID profile:(NSString*)profileID window:(NSString*)windowID {
  const auto id = base::SysNSStringToUTF8(extensionID);
  auto found = State().profiles.find(base::SysNSStringToUTF8(profileID));
  if (found == State().profiles.end() || found->second->IsOffTheRecord()) return NO;
  auto* profile = found->second;
  auto* extension = extensions::ExtensionRegistry::Get(profile)->GetInstalledExtension(id);
  if ([command isEqualToString:@"manage"] || [command isEqualToString:@"details"] || [command isEqualToString:@"options"] || [command isEqualToString:@"store"]) {
    GURL url([command isEqualToString:@"store"] ? "https://chromewebstore.google.com/" : "chrome://extensions/");
    if ([command isEqualToString:@"details"]) { if (!extension) return NO; url = GURL("chrome://extensions/?id=" + id); }
    if ([command isEqualToString:@"options"]) { if (!extension) return NO; url = extensions::OptionsPageInfo::GetOptionsPage(extension); if (!url.is_valid()) return NO; }
    auto* browser = BrowserFor(base::SysNSStringToUTF8(profileID), base::SysNSStringToUTF8(windowID));
    if (!browser) return NO;
    NavigateParams params(browser, url, ui::PAGE_TRANSITION_AUTO_TOPLEVEL);
    params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
    params.window_action = NavigateParams::WindowAction::kNoAction;
    Navigate(&params); return YES;
  }
  if (!extension || !extensions::ExtensionSystem::Get(profile)->management_policy()->UserMayModifySettings(extension, nullptr)) return NO;
  auto* registrar = extensions::ExtensionRegistrar::Get(profile);
  if ([command isEqualToString:@"enable"]) registrar->EnableExtension(id);
  else if ([command isEqualToString:@"disable"]) registrar->DisableExtension(id, {extensions::disable_reason::DISABLE_USER_ACTION});
  else if ([command isEqualToString:@"remove"]) { std::u16string error; return registrar->UninstallExtension(id, extensions::UNINSTALL_REASON_USER_INITIATED, &error); }
  else if ([command isEqualToString:@"pin"] || [command isEqualToString:@"unpin"]) {
    auto* model = ToolbarActionsModel::Get(profile);
    if (!model || !model->HasAction(id) || model->IsActionForcePinned(id)) return NO;
    model->SetActionVisibility(id, [command isEqualToString:@"pin"]);
  } else return NO;
  return YES;
}
- (BOOL)installExtension:(NSString*)extensionID package:(NSString*)path profile:(NSString*)profileID window:(NSString*)windowID
              completion:(void (^)(BOOL, NSString*))completion {
  CHECK(NSThread.isMainThread);
  const std::string id = base::SysNSStringToUTF8(extensionID);
  auto found = State().profiles.find(base::SysNSStringToUTF8(profileID));
  NSWindow* window = [NSClassFromString(@"CrestRoot") windowForIdentifier:windowID];
  if (found == State().profiles.end() || found->second->IsOffTheRecord() || !window ||
      id.size() != 32 || id.find_first_not_of("abcdefghijklmnop") != std::string::npos) return NO;
  auto prompt = std::make_unique<ExtensionInstallPrompt>(found->second, gfx::NativeWindow(window),
      std::make_unique<extensions::InstallPromptData>(extensions::InstallPromptData::UNSET_PROMPT_TYPE));
  prompt->SetSkipPostInstallUI(true);
  auto installer = extensions::CrxInstaller::Create(found->second, std::move(prompt));
  installer->set_expected_id(id);
  installer->set_is_gallery_install(true);
  installer->set_delete_source(true);
  // Each target profile independently verifies CRX3 signature and publisher proof.
  installer->AddInstallerCallback(base::BindOnce(^(const std::optional<extensions::CrxInstallError>& error) {
    completion(!error, error ? base::SysUTF16ToNSString(error->message()) : @"");
  }));
  installer->InstallCrx(base::FilePath(base::SysNSStringToUTF8(path)));
  return YES;
}
- (NSDictionary<NSString*, id>*)mediaActivityForPage:(NSString*)pageID {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  auto* contents = page ? page->web_contents() : nullptr;
  if (!contents) return nil;
  auto indicator = MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator();
  return @{
    @"playing": @(contents->IsCurrentlyAudible() || contents->GetCurrentlyPlayingVideoCount() > 0),
    @"capturing": @(contents->IsBeingCaptured() || indicator->IsCapturingUserMedia(contents)
                     || indicator->IsCapturingTab(contents) || indicator->IsCapturingWindow(contents)
                     || indicator->IsCapturingDisplay(contents)),
    @"pictureInPicture": @(contents->HasPictureInPictureVideo() || contents->HasPictureInPictureDocument())
  };
}
- (void)capturePage:(NSString*)pageID rect:(NSRect)rect width:(CGFloat)width
         completion:(void (^)(NSImage*))completion {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  auto* view = page && page->web_contents() ? page->web_contents()->GetRenderWidgetHostView() : nullptr;
  if (!view || !std::isfinite(width) || width < 0 || width > 16384 ||
      !std::isfinite(rect.origin.x) || !std::isfinite(rect.origin.y) ||
      !std::isfinite(rect.size.width) || !std::isfinite(rect.size.height)) {
    completion(nil);
    return;
  }
  gfx::Rect area = NSIsEmptyRect(rect) ? gfx::Rect() : gfx::Rect(
      static_cast<int>(rect.origin.x), static_cast<int>(rect.origin.y),
      static_cast<int>(rect.size.width), static_cast<int>(rect.size.height));
  if (!area.IsEmpty()) area.Intersect(gfx::Rect(view->GetViewBounds().size()));
  if (!NSIsEmptyRect(rect) && area.IsEmpty()) { completion(nil); return; }
  gfx::Size size = area.IsEmpty() ? view->GetViewBounds().size() : area.size();
  if (size.IsEmpty()) { completion(nil); return; }
  gfx::Size output;
  if (width > 0) output = gfx::Size(std::max(1, static_cast<int>(width)),
      std::max(1, static_cast<int>(width * size.height() / size.width())));
  auto reply = [completion copy];
  view->CopyFromSurface(area, output, base::Seconds(2), base::BindOnce(
      [](void (^reply)(NSImage*), const content::CopyFromSurfaceResult& result) {
        if (!result.has_value()) {
          dispatch_async(dispatch_get_main_queue(), ^{ reply(nil); });
          return;
        }
        SkBitmap bitmap = result->bitmap;
        dispatch_async(dispatch_get_main_queue(), ^{
          reply(bitmap.drawsNothing() ? nil : gfx::Image::CreateFrom1xBitmap(bitmap).ToNSImage());
        });
      }, reply));
}
- (void)exportPage:(NSString*)pageID format:(NSString*)format width:(CGFloat)width
        completion:(void (^)(NSData*, NSString*))completion {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents() || page->closing || State().disposing) {
    completion(nil, @"The page is unavailable."); return;
  }
  if (!page->document_service)
    page->document_service = std::make_unique<PageDocumentService>(page->web_contents());
  page->document_service->Export(format, width, completion);
}
- (BOOL)addContentScript:(NSString*)source page:(NSString*)pageID mainFrameOnly:(BOOL)mainFrameOnly {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents() || !source.length) return NO;
  page->content_scripts.emplace_back(base::SysNSStringToUTF8(source), mainFrameOnly);
  // A bridge that can see credentials replaces the engine's own password
  // manager, which would otherwise save into the engine profile and offer
  // fills Crest's vault never sees.
  if (auto* profile = Profile::FromBrowserContext(page->web_contents()->GetBrowserContext()))
    profile->GetPrefs()->SetBoolean(password_manager::prefs::kCredentialsEnableService, false);
  return YES;
}
- (void)evaluateContentScript:(NSString*)source page:(NSString*)pageID frame:(NSString*)frameID
                   completion:(void (^)(NSString* _Nullable))completion {
  CHECK(NSThread.isMainThread);
  auto parts = base::SplitString(base::SysNSStringToUTF8(frameID), ":", base::KEEP_WHITESPACE, base::SPLIT_WANT_ALL);
  int child = 0, routing = 0;
  Page* page = FindPage(pageID);
  if (!page || !page->web_contents() || parts.size() != 3 || !base::StringToInt(parts[0], &child) ||
      !base::StringToInt(parts[1], &routing)) { completion(nil); return; }
  auto* frame = content::RenderFrameHost::FromID(content::GlobalRenderFrameHostId(child, routing));
  if (!frame || !frame->IsRenderFrameLive() ||
      content::WebContents::FromRenderFrameHost(frame) != page->web_contents()) { completion(nil); return; }
  auto doc = base::WriteJson(base::Value(parts[2]));
  // The source runs only in the document it was addressed to.
  const std::string script = "(async () => { if (globalThis.__crestBridge?.doc !== " + *doc +
      ") return null;\n" + base::SysNSStringToUTF8(source) + "\n})()";
  void (^reply)(NSString*) = [completion copy];
  // A document torn down mid-evaluation drops its reply; the caller still
  // gets an answer.
  frame->ExecuteJavaScriptInIsolatedWorld(base::UTF8ToUTF16(script),
      mojo::WrapCallbackWithDefaultInvokeIfNotRun(
          base::BindOnce([](void (^reply)(NSString*), base::Value value) {
            auto json = base::WriteJson(value);
            reply(json ? base::SysUTF8ToNSString(*json) : nil);
          }, reply), base::Value()), crest::kContentWorldID);
}
- (BOOL)findInPage:(NSString*)pageID query:(NSString*)query backwards:(BOOL)backwards
     caseSensitive:(BOOL)caseSensitive completion:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  Page* page = FindPage(pageID);
  if (!page || !page->find_helper) return NO;
  page->find_completion = nil;
  if (!query.length) {
    page->find_helper->StopFinding(find_in_page::SelectionAction::kClear);
    completion(NO);
  } else {
    page->find_completion = [completion copy];
    page->find_helper->StartFinding(base::SysNSStringToUTF16(query), !backwards, caseSensitive, true);
  }
  return YES;
}
- (void)disposePages:(NSArray<NSString*>*)pageIDs windows:(NSArray<NSString*>*)windowIDs
    releaseProfiles:(NSArray<NSString*>*)profileIDs {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  // A Space-scoped popup is anchored in one of the windows or profiles being
  // released, and nothing else would close it.
  if (windowIDs.count || profileIDs.count) state.space_extension_popup.reset();
  for (NSString* identifier in pageIDs) {
    state.creating_pages.erase(base::SysNSStringToUTF8(identifier));
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
    // A sign-in window closed before its page reached the callback.
    EndAuthenticationSession(id, nil, false);
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
    state.extension_observers.erase(id);
    state.profiles.erase(found);
    if (profile->IsOffTheRecord()) ProfileDestroyer::DestroyOTRProfileWhenAppropriate(profile);
    state.profile_leases.erase(id);
  }
}
- (void)deleteProfile:(NSString*)profileID ephemeral:(BOOL)ephemeral completion:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  const std::string id = base::SysNSStringToUTF8(profileID);
  auto* manager = g_browser_process->profile_manager();
  if (!manager || state.disposing || !base::Uuid::ParseCaseInsensitive(id).is_valid() || state.profile_deletions.contains(id)) {
    completion(NO); return;
  }
  auto found = state.profiles.find(id);
  Profile* profile = found == state.profiles.end() ? nullptr : found->second;
  if (ephemeral && profile && !profile->IsOffTheRecord()) { completion(NO); return; }
  const base::FilePath path = manager->user_data_dir().AppendASCII("Crest-" + id);
  if (profile == state.root_profile || (profile && !profile->IsOffTheRecord() && profile->GetPath() != path)) {
    completion(NO); return;
  }
  state.deleting_profiles.insert(id);
  std::set<std::string> released{id};
  if (profile && !profile->IsOffTheRecord()) {
    for (const auto& [key, candidate] : state.profiles)
      if (candidate->GetOriginalProfile() == profile) released.insert(key);
  }
  NSMutableArray<NSString*>* pages = [NSMutableArray array];
  NSMutableArray<NSString*>* profiles = [NSMutableArray array];
  for (const auto& key : released) {
    state.deleting_profiles.insert(key);
    [profiles addObject:base::SysUTF8ToNSString(key)];
  }
  std::erase_if(state.creating_pages, [&](const auto& entry) { return released.contains(entry.second); });
  for (const auto& [key, page] : state.pages)
    if (released.contains(page->profile)) [pages addObject:base::SysUTF8ToNSString(key)];
  // Hold the regular profile while releasing browsers and Crest's runtime leases.
  auto keep_alive = profile && !profile->IsOffTheRecord() ?
      std::make_unique<ScopedProfileKeepAlive>(profile, ProfileKeepAliveOrigin::kProfileDeletionProcess) : nullptr;
  [self disposePages:pages windows:@[] releaseProfiles:profiles];
  if (state.browser_observation) state.browser_observation(@{ @"deletedProfile": profileID });
  if (ephemeral) { completion(YES); return; }
  if (!manager->GetProfileAttributesStorage().GetProfileAttributesWithPath(path) &&
      !manager->GetProfileByPath(path) && !base::PathExists(path)) { completion(YES); return; }
  auto deletion = std::make_unique<NativeProfileDeletion>(id, path, completion);
  auto* pending = deletion.get();
  state.profile_deletions.emplace(id, std::move(deletion));
  if (auto* loaded = manager->GetProfileByPath(path)) { pending->Start(loaded); return; }
  if (IsProfileDirectoryMarkedForDeletion(path)) { pending->Finish(false); return; }
  manager->CreateProfileAsync(path, base::BindOnce([](std::string id, Profile* loaded) {
    auto found = State().profile_deletions.find(id);
    if (found != State().profile_deletions.end()) found->second->Start(loaded);
  }, id));
}
- (void)disposePages {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  state.disposing = true;
  CancelAllAuthenticationSessions();
  state.browser_observation = nil;
  state.space_extension_popup.reset();
  state.adoptions.clear();
  state.pending_link_navigations.clear();
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
  state.extension_observers.clear();
  state.profiles.clear();
  state.profile_leases.clear();
}
- (void)prepareToClosePages:(NSArray<NSString*>*)pageIDs windows:(NSArray<NSString*>*)windowIDs
                completion:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  if (state.close_preflight || state.quit_preflight || state.disposing) { completion(NO); return; }
  std::set<std::string> selected;
  for (NSString* id in pageIDs) selected.insert(base::SysNSStringToUTF8(id));
  for (NSString* id in windowIDs) state.close_windows.insert(base::SysNSStringToUTF8(id));
  for (const auto& [id, page] : state.pages) {
    bool matches = selected.contains(id);
    for (const auto& [key, owner] : state.browsers)
      if (owner->browser == page->browser && state.close_windows.contains(owner->window)) matches = true;
    if (!matches || !page->web_contents()) continue;
    state.close_pages.push_back(id);
    state.close_revisions.emplace(id, page->navigation_revision);
  }
  state.close_preflight = [completion copy];
  AdvancePageClosePreparation(++state.close_generation, true);
}
- (void)prepareToQuit:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  if (state.quit_preflight || state.close_preflight || state.disposing || !state.profile_deletions.empty()) { completion(NO); return; }
  state.quit_preflight = [completion copy];
  ContinueQuitPreparation(++state.quit_generation, true);
}
- (void)cancelAuthenticationSessionForWindow:(NSString*)windowID {
  CHECK(NSThread.isMainThread);
  EndAuthenticationSession(base::SysNSStringToUTF8(windowID), nil, false);
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
bool RouteModifiedLink(content::WebContents* source, content::OpenURLParams& params) {
  if (!IsEnabled() || !params.crest_link_modifiers) return false;
  if (!State().disposing && source && params.crest_link_modifiers <= 15 &&
      (params.crest_link_modifiers & 11) && params.is_renderer_initiated && params.user_gesture &&
      params.triggering_event_info == blink::mojom::TriggeringEventInfo::kFromTrustedEvent &&
      !params.started_from_context_menu && !params.post_data && params.url.SchemeIsHTTPOrHTTPS() &&
      params.url.spec().size() <= 8192) {
    for (auto& [id, page] : State().pages) {
      if (page->web_contents() != source || page->closing || !page->modified_link_handler) continue;
      const std::string token = base::Uuid::GenerateRandomV4().AsLowercaseString();
      __block NSString* decision = nil;
      __block CrestDeferredNavigation present = nil;
      page->modified_link_handler(base::SysUTF8ToNSString(params.url.spec()), params.crest_link_modifiers,
          base::SysUTF8ToNSString(token), ^(NSString* value, CrestDeferredNavigation action) {
            decision = [value copy]; present = [action copy];
          });
      if ([decision isEqualToString:@"foregroundTab"] || [decision isEqualToString:@"backgroundTab"]) {
        params.disposition = [decision isEqualToString:@"foregroundTab"]
            ? WindowOpenDisposition::NEW_FOREGROUND_TAB : WindowOpenDisposition::NEW_BACKGROUND_TAB;
        params.crest_download_fallback = nullptr;
        return false;
      }
      if ([decision isEqualToString:@"peekModifier"] && present && State().pending_link_navigations.size() < 32) {
        auto weak = source->GetWeakPtr();
        const auto revision = page->navigation_revision;
        const auto generation = page->navigation_generation;
        params.crest_download_fallback = nullptr;
        State().pending_link_navigations.emplace(token,
            PendingLinkNavigation{params, weak, page->profile, revision, generation});
        dispatch_async(dispatch_get_main_queue(), ^{
          if (!State().disposing && weak) {
            for (auto& [current_id, current] : State().pages) {
              if (current->web_contents() == weak.get() && !current->closing &&
                  current->navigation_revision == revision && current->navigation_generation == generation) {
                present(); return;
              }
            }
          }
          State().pending_link_navigations.erase(token);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
          State().pending_link_navigations.erase(token);
        });
        return true;
      }
      break;
    }
  }
  // Unowned pages and declined Peek retain the original renderer download path,
  // including Chromium's download validation and restrictions.
  if (params.disposition == WindowOpenDisposition::SAVE_TO_DISK &&
      params.crest_download_fallback && params.crest_download_fallback->data) {
    std::move(params.crest_download_fallback->data).Run();
    return true;
  }
  return false;
}

namespace {
class LinkNavigationThrottle final : public content::NavigationThrottle {
 public:
  explicit LinkNavigationThrottle(content::NavigationThrottleRegistry& registry)
      : NavigationThrottle(registry) {}
  const char* GetNameForLogging() override { return "CrestLinkNavigationThrottle"; }
  ThrottleCheckResult WillStartRequest() override {
    auto* navigation = navigation_handle();
    // Only an actual link in an owned page can protect a saved tab. Forms,
    // scripts, browser commands, subframes and redirects keep engine semantics.
    if (State().disposing || !navigation->IsInPrimaryMainFrame() ||
        !navigation->IsRendererInitiated() || !navigation->HasUserGesture() ||
        !navigation->WasInitiatedByLinkClick() || navigation->IsFormSubmission() ||
        navigation->WasStartedFromContextMenu() || navigation->IsPost() ||
        !navigation->GetURL().SchemeIsHTTPOrHTTPS() || navigation->GetURL().spec().size() > 8192)
      return PROCEED;
    auto* contents = navigation->GetWebContents();
    for (auto& [id, page] : State().pages) {
      if (page->web_contents() != contents || !page->protected_link_handler) continue;
      auto action = page->protected_link_handler(base::SysUTF8ToNSString(navigation->GetURL().spec()));
      if (!action) return PROCEED;
      auto weak = contents->GetWeakPtr();
      const auto revision = page->navigation_revision;
      const auto generation = page->navigation_generation;
      // Do not mount/reparent native content while Chromium's navigation stack
      // is live. A later navigation or teardown invalidates this presentation.
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!weak || State().disposing) return;
        for (auto& [current_id, current] : State().pages) {
          if (current->web_contents() == weak.get() && current->navigation_revision == revision &&
              current->navigation_generation == generation) { action(); return; }
        }
      });
      return CANCEL_AND_IGNORE;
    }
    return PROCEED;
  }
};
}  // namespace

namespace {
bool MatchesAuthenticationCallback(ASWebAuthenticationSessionRequest* request, const GURL& url) {
  NSURL* candidate = net::NSURLWithGURL(url);
  if (!candidate) return false;
  if (@available(macOS 14.4, *)) return [request.callback matchesURL:candidate];
  return request.callbackURLScheme.length &&
      [candidate.scheme caseInsensitiveCompare:request.callbackURLScheme] == NSOrderedSame;
}

class AuthenticationSessionThrottle final : public content::NavigationThrottle {
 public:
  explicit AuthenticationSessionThrottle(content::NavigationThrottleRegistry& registry)
      : NavigationThrottle(registry) {}
  const char* GetNameForLogging() override { return "CrestAuthenticationSessionThrottle"; }
  ThrottleCheckResult WillStartRequest() override { return Check(); }
  ThrottleCheckResult WillRedirectRequest() override { return Check(); }

 private:
  ThrottleCheckResult Check() {
    auto& state = State();
    auto* navigation = navigation_handle();
    if (state.authentication_sessions.empty() || state.disposing || !navigation->IsInPrimaryMainFrame())
      return PROCEED;
    Browser* browser = nullptr;
    for (const auto& [id, page] : state.pages)
      if (page->web_contents() == navigation->GetWebContents()) { browser = page->browser; break; }
    if (!browser) return PROCEED;
    for (const auto& [key, owner] : state.browsers) {
      if (owner->browser != browser) continue;
      auto session = state.authentication_sessions.find(owner->window);
      if (session == state.authentication_sessions.end() ||
          !MatchesAuthenticationCallback(session->second, navigation->GetURL())) return PROCEED;
      // Completing closes the window and destroys this navigation's page, so
      // it happens after the navigation stack has unwound.
      NSURL* callback = net::NSURLWithGURL(navigation->GetURL());
      const std::string window = owner->window;
      dispatch_async(dispatch_get_main_queue(), ^{ EndAuthenticationSession(window, callback, true); });
      return CANCEL_AND_IGNORE;
    }
    return PROCEED;
  }
};
}  // namespace

void AddNavigationThrottle(content::NavigationThrottleRegistry& registry) {
  if (!IsEnabled()) return;
  registry.AddThrottle(std::make_unique<LinkNavigationThrottle>(registry));
  registry.AddThrottle(std::make_unique<AuthenticationSessionThrottle>(registry));
}

bool BeginLinkDrag(content::WebContents* contents, const content::DropData& data) {
  // File, image, selection and custom payload drags retain Chromium's native path.
  // Chromium adds its own drag ID to every payload, including ordinary links.
  if (!IsEnabled() || State().disposing || data.url_infos.size() != 1 ||
      !data.url_infos[0].url.SchemeIsHTTPOrHTTPS() || data.url_infos[0].url.spec().size() > 8192 ||
      data.download_metadata || !data.filenames.empty() || !data.file_system_files.empty() ||
      !data.file_contents.empty() || data.file_contents_source_url.is_valid() ||
      std::any_of(data.custom_data.begin(), data.custom_data.end(),
          [](const auto& entry) { return entry.first != u"chromium/x-drag-id"; }) || !data.text ||
      *data.text != base::UTF8ToUTF16(data.url_infos[0].url.spec())) return false;
  auto* focused_frame = contents->GetFocusedFrame();
  if (!focused_frame || !focused_frame->GetView() ||
      !focused_frame->GetView()->GetSelectedText().empty()) return false;
  for (auto& [id, page] : State().pages) {
    if (page->web_contents() == contents && page->link_handler)
      return page->link_handler(@"drag", base::SysUTF8ToNSString(data.url_infos[0].url.spec()),
          base::SysUTF16ToNSString(data.url_infos[0].title));
  }
  return false;
}

void AppendLinkMenuItem(NSMenu* menu, content::WebContents* contents, const GURL& url) {
  if (!IsEnabled() || State().disposing || !url.SchemeIsHTTPOrHTTPS()) return;
  for (auto& [id, page] : State().pages) {
    if (page->web_contents() != contents || !page->link_handler) continue;
    NSString* address = base::SysUTF8ToNSString(url.spec());
    auto weak = contents->GetWeakPtr();
    const uint64_t revision = page->navigation_revision;
    // Each row is bound to the source page and its navigation revision: the
    // engine answers availability now, and the action re-resolves the same page
    // after menu tracking ends rather than holding a raw page pointer.
    auto append = [&](NSString* title, NSString* invocation) {
      // A block written inside this lambda cannot read the enclosing function's
      // locals through the lambda's own by-reference captures: the lambda is
      // gone long before a menu action runs, so those references dangle and the
      // action silently declines. Copy what the action needs into this scope,
      // where the block captures each value itself.
      const base::WeakPtr<content::WebContents> source = weak;
      NSString* const destination = address;
      const uint64_t expected_revision = revision;
      CrestLinkMenuAction* action = [[CrestLinkMenuAction alloc] init];
      action.run = ^{
        // Return from menu tracking before mounting native UI or mutating the
        // owning window's tab state.
        dispatch_async(dispatch_get_main_queue(), ^{
          if (!source || State().disposing) return;
          for (auto& [current_id, current] : State().pages) {
            if (current->web_contents() == source.get() &&
                current->navigation_revision == expected_revision && current->link_handler) {
              current->link_handler(invocation, destination, @"");
              return;
            }
          }
        });
      };
      NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:@selector(invoke:) keyEquivalent:@""];
      item.target = action;
      item.representedObject = action;
      // MenuControllerCocoa maps existing items by model index. Append native
      // actions so asynchronous engine updates still address their original rows.
      [menu addItem:item];
    };
    const bool can_peek = page->link_handler(@"can_peek", address, @"");
    const bool can_split = page->link_handler(@"can_split", address, @"");
    if (!can_peek && !can_split) return;
    [menu addItem:NSMenuItem.separatorItem];
    if (can_peek) append(@"Open Link in Peek", @"peek");
    if (can_split) append(@"Open Link in Split View", @"split");
    return;
  }
}

bool OwnsDownload(download::DownloadItem* item) {
  if (!IsEnabled() || State().disposing || item->IsTransient() ||
      item->GetMimeType() == "application/x-chrome-extension") return false;
  for (const auto& [id, profile] : State().profiles)
    if (profile == content::DownloadItemUtils::GetBrowserContext(item)) return true;
  return false;
}

void PublishDownload(download::DownloadItem* item) {
  auto values = DownloadValues(item);
  if (!values || !State().download_observation) return;
  // Capture a value snapshot before returning to the engine. Native UI or
  // cancellation must never destroy a WebContents on this notification stack.
  dispatch_async(dispatch_get_main_queue(), ^{
    if (State().disposing || !State().download_observation) return;
    State().download_observation(values);
    if ([values[@"state"] isEqual:@"failed"]) {
      if (auto* current = FindDownload(values[@"profileId"], values[@"downloadId"]);
          current && current->GetState() == download::DownloadItem::IN_PROGRESS) {
        bool blocked;
        DownloadWarning(current, &blocked);
        if (blocked) current->Cancel(true);
      }
    }
  });
}

void ChooseDownloadDestination(download::DownloadItem* item,
    const base::FilePath& suggested_path, DownloadConfirmationReason reason,
    DownloadTargetDeterminerDelegate::ConfirmationCallback callback) {
  auto values = DownloadValues(item);
  // DLP and managed targets retain Chromium's policy path. This callback is
  // reached only after its normal filename and path reservation checks.
  if (!values || !State().download_destination || reason == DownloadConfirmationReason::DLP_BLOCKED) {
    std::move(callback).Run(DownloadConfirmationResult::CANCELED, ui::SelectedFileInfo());
    return;
  }
  values[@"filename"] = base::SysUTF8ToNSString(suggested_path.BaseName().AsUTF8Unsafe());
  values[@"forcePrompt"] = @(reason != DownloadConfirmationReason::NONE && reason != DownloadConfirmationReason::PREFERENCE);
  auto reply = std::make_shared<DownloadTargetDeterminerDelegate::ConfirmationCallback>(std::move(callback));
  State().download_destination(values, ^(NSString* path) {
    if (!*reply) return;
    auto* current = FindDownload(values[@"profileId"], values[@"downloadId"]);
    if (!path.length || !current || current->GetState() != download::DownloadItem::IN_PROGRESS) {
      std::move(*reply).Run(DownloadConfirmationResult::CANCELED, ui::SelectedFileInfo());
      return;
    }
    // Destination resolution alone never grants a safety override, even when
    // the native resolver used a save panel. Chromium still checks the file.
    std::move(*reply).Run(DownloadConfirmationResult::CONTINUE_WITHOUT_CONFIRMATION,
        ui::SelectedFileInfo(base::FilePath(base::SysNSStringToUTF8(path))));
  });
}

bool CompletePageClosePreparation(content::WebContents* contents, bool proceed) {
  auto& state = State();
  if (!state.close_preflight || state.close_pending.empty()) return false;
  auto found = state.pages.find(state.close_pending);
  if (found == state.pages.end() || found->second->web_contents() != contents) return false;
  state.close_pending.clear();
  const auto generation = state.close_generation;
  dispatch_async(dispatch_get_main_queue(), ^{ AdvancePageClosePreparation(generation, proceed); });
  return true;
}
void ShowExtensionPrompt(
    std::unique_ptr<ExtensionInstallPromptShowParams> params,
    ExtensionInstallPrompt::DoneCallback callback,
    std::unique_ptr<extensions::InstallPromptData> prompt) {
  using Result = extensions::ExtensionInstallPromptClient::Result;
  using Payload = ExtensionInstallPrompt::DoneCallbackPayload;
  NSWindow* window = params->GetParentWindow().GetNativeNSWindow();
  if (!window || window.attachedSheet || params->WasParentDestroyed() || prompt->requires_parent_permission()) {
    std::move(callback).Run(Payload(Result::ABORTED));
    return;
  }
  struct PendingPrompt {
    std::unique_ptr<ExtensionInstallPromptShowParams> params;
    ExtensionInstallPrompt::DoneCallback callback;
    std::unique_ptr<extensions::InstallPromptData> prompt;
  };
  auto pending = std::make_shared<PendingPrompt>(std::move(params), std::move(callback), std::move(prompt));
  if (State().extension_review && pending->prompt->extension() &&
      pending->prompt->type() == extensions::InstallPromptData::INSTALL_PROMPT) {
    auto* extension = pending->prompt->extension();
    NSMutableArray* permissions = [NSMutableArray array];
    const auto permission_details = pending->prompt->GetPermissions();
    for (size_t i = 0; i < pending->prompt->GetPermissionCount(); ++i) {
      [permissions addObject:base::SysUTF16ToNSString(pending->prompt->GetPermission(i))];
      if (i < permission_details.details.size() && !permission_details.details[i].empty())
        [permissions addObject:base::SysUTF16ToNSString(permission_details.details[i])];
    }
    NSDictionary* values = @{@"id": base::SysUTF8ToNSString(extension->id()),
      @"name": base::SysUTF8ToNSString(extension->name()), @"version": base::SysUTF8ToNSString(extension->version().GetString()),
      @"description": base::SysUTF8ToNSString(extension->manifest()->FindStringPath("description") ? *extension->manifest()->FindStringPath("description") : std::string()), @"permissions": permissions,
      @"icon": pending->prompt->icon().IsEmpty() ? (id)NSNull.null : pending->prompt->icon().ToNSImage(),
      @"canWithhold": @(extensions::util::CanWithholdPermissionsFromExtension(*extension)),
      @"withhold": @(pending->prompt->ShouldWithheldPermissionsOnDialogAccept())};
    State().extension_review(values, window, ^(BOOL accepted, BOOL withhold) {
      if (!pending->callback) return;
      Result result = Result::USER_CANCELED;
      if (pending->params->WasParentDestroyed()) result = Result::ABORTED;
      else if (accepted) { result = withhold ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS : Result::ACCEPTED; pending->prompt->OnDialogAccepted(); }
      else pending->prompt->OnDialogCanceled();
      std::move(pending->callback).Run(Payload(result));
    });
    return;
  }
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = base::SysUTF16ToNSString(pending->prompt->GetDialogTitle());
  NSMutableArray* messages = [NSMutableArray array];
  if (pending->prompt->GetPermissionCount()) {
    [messages addObject:base::SysUTF16ToNSString(pending->prompt->GetPermissionsHeading())];
    for (size_t i = 0; i < pending->prompt->GetPermissionCount(); ++i)
      [messages addObject:base::SysUTF16ToNSString(pending->prompt->GetPermission(i))];
  }
  const bool withhold = pending->prompt->ShouldWithheldPermissionsOnDialogAccept();
  if (withhold) [messages addObject:@"Website access is withheld until you grant it in extension settings."];
  alert.informativeText = [messages componentsJoinedByString:@"\n\n"];
  NSString* accept = base::SysUTF16ToNSString(pending->prompt->GetAcceptButtonLabel());
  if (accept.length) [alert addButtonWithTitle:accept];
  [alert addButtonWithTitle:base::SysUTF16ToNSString(pending->prompt->GetAbortButtonLabel())];
  if (accept.length) {
    alert.buttons.firstObject.enabled = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      alert.buttons.firstObject.enabled = YES;
    });
  }
  id closed = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
      object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*) {
    if (alert.window.sheetParent) [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
  }];
  [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    [[NSNotificationCenter defaultCenter] removeObserver:closed];
    Result result = Result::USER_CANCELED;
    if (pending->params->WasParentDestroyed()) result = Result::ABORTED;
    else if (accept.length && response == NSAlertFirstButtonReturn) {
      result = withhold ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS : Result::ACCEPTED;
      pending->prompt->OnDialogAccepted();
    } else pending->prompt->OnDialogCanceled();
    std::move(pending->callback).Run(Payload(result));
  }];
}
std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* contents, permissions::PermissionPrompt::Delegate* delegate) {
  if (delegate->ShouldDropCurrentRequestIfCannotShowQuietly()) return nullptr;
  BrowserWindowInterface* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  NSWindow* window = browser ? WindowForBrowser(browser->GetBrowserForMigrationOnly()) : nil;
  if (!window || window.attachedSheet) return nullptr;
  return std::make_unique<NativePermissionPrompt>(window, delegate);
}
namespace {
bool HasBundleMarker(NSString* name) {
  NSString* path = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name];
  return path && [NSFileManager.defaultManager fileExistsAtPath:path];
}
// A product bundle hosts the native Crest UI for every launch, including the
// ones Crest cannot add switches to: Finder, login items, the default-browser
// role and Dock reopen. Experiment bundles keep requiring the explicit switch.
bool IsProductBundle() {
  static const bool product = HasBundleMarker(@"Crest-Native-Host");
  return product;
}
}  // namespace
bool IsEnabled() {
  static const bool enabled =
      IsProductBundle() || base::CommandLine::ForCurrentProcess()->HasSwitch("crest-control-plane");
  return enabled;
}
void OnBrowserWindowCreated(Browser* browser) {
  if (!State().bootstrap) {
    State().bootstrap = browser;
    State().root_profile = browser->GetProfile()->GetOriginalProfile();
  }
  if (!State().started || !State().creating_window.empty()) return;
  if (RegisterEngineBrowser(browser)) return;
  // `CanCreateEngineBrowser` refuses these before they are created, so this is
  // only reached by a creation path that does not consult it. The Browser is
  // still tracked so its tabs are offered and then declined, rather than left
  // running unowned.
  const std::string key = "native/" + base::Uuid::GenerateRandomV4().AsLowercaseString();
  State().browsers.emplace(key, std::make_unique<BrowserOwner>(browser, std::string()));
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
  // An experiment bundle must name its own engine profile root. A product
  // bundle uses Chromium's default directory for its own bundle identity.
  CHECK(IsProductBundle() || base::CommandLine::ForCurrentProcess()->HasSwitch("user-data-dir"));
  // The review and product compositions keep separate framework names so a
  // package can only ever contain the one it was assembled from.
  NSBundle* bundle = nil;
  for (NSString* name in @[ @"CrestChromiumUI.framework", @"CrestChromiumUIProduct.framework" ]) {
    NSString* path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:name];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
    bundle = [NSBundle bundleWithPath:path];
    break;
  }
  CHECK(bundle);
  NSError* error = nil;
  CHECK([bundle loadAndReturnError:&error]) << base::SysNSStringToUTF8(error.description);
  CHECK(NSClassFromString(@"CrestRoot"));
  State().started = true;
  [NSClassFromString(@"CrestRoot") startWithHost:[[CrestChromiumHost alloc] init]];
  auto pending = std::move(State().pending_authentication_sessions);
  State().pending_authentication_sessions.clear();
  for (ASWebAuthenticationSessionRequest* request : pending) StartAuthenticationSession(request);
}
void OnEngineWindowShown(Browser* browser, bool focused) {
  if (!State().started) return;
  for (const auto& [key, owner] : State().browsers) {
    if (owner->browser != browser || !owner->engine_window || owner->presented) continue;
    // `chrome.windows.create` with `focused: false` reaches ShowInactive().
    owner->focused = focused;
    return;
  }
}
bool CanCreateEngineBrowser(Profile* profile) {
  // Before the core runs, and for the window the core is creating for itself,
  // the engine's own answer stands.
  if (!IsEnabled() || !State().started || !State().creating_window.empty()) return true;
  if (State().disposing || State().quitting) return true;
  std::string profile_id;
  for (const auto& [id, candidate] : State().profiles)
    if (candidate == profile) { profile_id = id; break; }
  if (profile_id.empty() || State().deleting_profiles.contains(profile_id)) return false;
  NSDictionary<NSString*, NSString*>* placement = [NSClassFromString(@"CrestRoot")
      reserveEngineWindowForProfile:base::SysUTF8ToNSString(profile_id)];
  return placement[@"windowId"].length > 0 && placement[@"spaceId"].length > 0;
}
NSWindow* WindowForBrowser(Browser* browser) {
  if (!State().started) return nil;
  for (const auto& [key, owner] : State().browsers) {
    if (owner->browser != browser || owner->window.empty()) continue;
    // A reserved engine window has an identifier before it has a window: a
    // renderer popup never opens the one reserved for it, because its tab is
    // adopted into the opener's window. Those Browsers keep the same fallback
    // they had before they carried an identifier at all.
    if (NSWindow* window = [NSClassFromString(@"CrestRoot")
            windowForIdentifier:base::SysUTF8ToNSString(owner->window)]) {
      return window;
    }
    break;
  }
  if (!State().creating_window.empty())
    return [NSClassFromString(@"CrestRoot") windowForIdentifier:base::SysUTF8ToNSString(State().creating_window)];
  return [NSClassFromString(@"CrestRoot") windowForIdentifier:nil];
}
bool DeferQuit() {
  return IsEnabled() && State().started && !State().quitting && [NSClassFromString(@"CrestRoot") deferQuit];
}
bool Reopen() {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return false;
  return [NSClassFromString(@"CrestRoot") reopen];
}
namespace {
// Hands one panel request to the core, which owns the card.
bool RouteSidePanel(content::WebContents* contents, const std::string& extension_id,
                    CrestSidePanelRequest request) {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return false;
  const std::string page = PageIdentifierForContents(contents);
  if (page.empty()) return false;
  [NSClassFromString(@"CrestRoot") routeSidePanel:base::SysUTF8ToNSString(extension_id)
                                            page:base::SysUTF8ToNSString(page)
                                         request:request];
  return true;
}
}  // namespace
bool OpenExtensionSidePanel(content::WebContents* contents, const std::string& extension_id) {
  return RouteSidePanel(contents, extension_id, CrestSidePanelRequestOpen);
}
bool CloseExtensionSidePanel(content::WebContents* contents, const std::string& extension_id) {
  return RouteSidePanel(contents, extension_id, CrestSidePanelRequestClose);
}
bool CanDockDevTools(content::WebContents* inspected) {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return false;
  return !PageIdentifierForContents(inspected).empty();
}
bool UpdateDockedDevTools(content::WebContents* inspected) {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return false;
  const std::string identifier = PageIdentifierForContents(inspected);
  if (identifier.empty()) return false;
  Page* page = FindPage(base::SysUTF8ToNSString(identifier));
  if (!page) return false;
  auto* inspector = DevToolsWindow::GetInstanceForInspectedWebContents(inspected);
  DevToolsContentsResizingStrategy strategy;
  // Only a docked frontend belongs in the card. An undocked window also offers
  // its device-emulation container for the inspected tab, which Crest does not
  // present: the card keeps showing the page.
  content::WebContents* frontend = inspector && inspector->IsDocked()
      ? DevToolsWindow::GetInTabWebContents(inspected, &strategy) : nullptr;
  if (!frontend) {
    if (inspector && !inspector->IsDocked()) {
      if (content::WebContents* undocked = inspector->GetDevToolsWebContents())
        page->undocked_devtools = undocked->GetWeakPtr();
    }
    // Nothing is docked any more: the inspector closed, or the user undocked
    // it and Chromium has taken the frontend into a window of its own.
    if (!page->devtools) return true;
    page->devtools.reset();
  } else if (page->undocked_devtools.get() == frontend) {
    // The user re-docked the window they had undocked. That frontend can no
    // longer draw outside Views, so it is replaced with a fresh docked one.
    page->undocked_devtools.reset();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([](base::WeakPtr<content::WebContents> inspected,
                                     base::WeakPtr<content::WebContents> frontend) {
          if (frontend) frontend->Close();
          if (inspected) {
            DevToolsWindow::OpenDevToolsWindow(inspected.get(), DevToolsToggleAction::Show(),
                DevToolsOpenedByAction::kMainMenuOrMainShortcut);
          }
        }, inspected->GetWeakPtr(), frontend->GetWeakPtr()));
    return true;
  } else {
    if (!page->devtools || !page->devtools->hosts(frontend))
      page->devtools = std::make_unique<DevToolsPanel>(frontend);
    page->devtools->strategy.CopyFrom(strategy);
  }
  [NSClassFromString(@"CrestRoot") routeDevTools:base::SysUTF8ToNSString(identifier)];
  return true;
}
void OnDevToolsClosing(content::WebContents* inspected) {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return;
  const std::string identifier = PageIdentifierForContents(inspected);
  if (identifier.empty()) return;
  [NSClassFromString(@"CrestRoot") closeDevToolsPanel:base::SysUTF8ToNSString(identifier)];
}
bool OpenExternalURLs(NSArray<NSURL*>* urls) {
  // Before the native root exists there is nothing to route into, and after a
  // quit has been accepted there is nothing left to open. Chromium then keeps
  // its own behavior rather than dropping the request.
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return false;
  return [NSClassFromString(@"CrestRoot") openExternalURLs:urls];
}
bool BeginAuthenticationSession(ASWebAuthenticationSessionRequest* request) {
  CHECK(NSThread.isMainThread);
  if (!IsEnabled()) return false;
  if (!State().started) { State().pending_authentication_sessions.push_back(request); return true; }
  StartAuthenticationSession(request);
  return true;
}
bool CancelAuthenticationSession(ASWebAuthenticationSessionRequest* request) {
  CHECK(NSThread.isMainThread);
  if (!IsEnabled()) return false;
  auto& state = State();
  auto pending = std::find_if(state.pending_authentication_sessions.begin(),
      state.pending_authentication_sessions.end(),
      [&](ASWebAuthenticationSessionRequest* candidate) { return [candidate.UUID isEqual:request.UUID]; });
  if (pending != state.pending_authentication_sessions.end()) {
    state.pending_authentication_sessions.erase(pending);
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodeCanceledLogin
                                             userInfo:nil]];
    return true;
  }
  for (const auto& [window, candidate] : state.authentication_sessions) {
    if (![candidate.UUID isEqual:request.UUID]) continue;
    EndAuthenticationSession(std::string(window), nil, true);
    break;
  }
  return true;
}
void UpdateTargetURL(content::WebContents* contents, const GURL& url) {
  if (!IsEnabled() || !State().started || State().disposing || !contents) return;
  for (auto& [page_id, page] : State().pages) {
    if (page->web_contents() != contents) continue;
    page->observation(@"link_hover", @{
      @"url": url.is_valid() ? base::SysUTF8ToNSString(url.spec()) : (id)NSNull.null });
    return;
  }
}
void UpdateSiteIndicators(content::WebContents* contents) {
  if (!IsEnabled() || !State().started || State().disposing || !contents) return;
  for (auto& [id, page] : State().pages) {
    if (page->web_contents() != contents) continue;
    auto* blocker = blocked_content::PopupBlockerTabHelper::FromWebContents(contents);
    const size_t count = blocker ? blocker->GetBlockedPopupsCount() : 0;
    // The blocker forgets its pop-ups when the document changes.
    if (count < page->published_blocked_popups) page->published_blocked_popups = count;
    if (count > page->published_blocked_popups) {
      page->published_blocked_popups = count;
      page->observation(@"popup_blocked", @{
        @"url": base::SysUTF8ToNSString(contents->GetLastCommittedURL().spec()),
        @"count": @(count) });
    }
    return;
  }
}
void TranslateSelection(const std::u16string& text) {
  if (!IsEnabled() || !State().started || State().disposing || text.empty()) return;
  [NSClassFromString(@"CrestRoot") translateText:base::SysUTF16ToNSString(text)];
}
void ShowEngineNotice(const std::u16string& message, const std::string& symbol) {
  if (!IsEnabled() || !State().started || State().disposing || message.empty()) return;
  [NSClassFromString(@"CrestRoot") showNativeNotice:base::SysUTF16ToNSString(message)
                                               icon:base::SysUTF8ToNSString(symbol)];
}
}  // namespace crest
