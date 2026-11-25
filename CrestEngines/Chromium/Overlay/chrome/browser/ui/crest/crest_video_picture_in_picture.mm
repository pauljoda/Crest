#include "chrome/browser/ui/crest/crest_chrome_hooks.h"

#import <Cocoa/Cocoa.h>
#import <MediaAccessibility/MediaAccessibility.h>
#import <QuartzCore/QuartzCore.h>

#include <dlfcn.h>
#include <algorithm>

#include "base/apple/scoped_cftyperef.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "cc/layers/deadline_policy.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "components/viz/common/surfaces/surface_id.h"
#include "content/public/browser/context_factory.h"
#include "content/public/browser/overlay_window.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/accelerated_widget_mac/display_ca_layer_tree.h"
#include "ui/compositor/layer_surface.h"
#include "ui/compositor/recyclable_compositor_mac.h"
#include "ui/display/screen.h"
#include "ui/gfx/ca_layer_params.h"
#include "ui/gfx/geometry/size_conversions.h"
#include "ui/gfx/geometry/size_f.h"
#include "ui/gfx/mac/coordinate_conversion.h"

// The macOS system PiP controller also used by WebKit. Resolve the
// implementation at runtime so the engine can decline unsupported requests.
@protocol CrestSystemVideoPictureInPicture
- (void)setDelegate:(id)delegate;
- (void)setAspectRatio:(NSSize)size;
- (void)setUserCanResize:(BOOL)resizable;
- (void)setPlaying:(BOOL)playing;
- (void)presentViewControllerAsPictureInPicture:(NSViewController*)source;
- (void)dismissViewController:(NSViewController*)source;
@end

using CrestPictureInPictureBehavior = PictureInPictureWindowManager::UiBehavior;

@interface CrestPictureInPictureVideoView : NSView
@property(nonatomic, copy) void (^didResize)(void);
@property(nonatomic, weak) NSView* inlineSuperview;
@end

@implementation CrestPictureInPictureVideoView
@synthesize didResize = _didResize;
@synthesize inlineSuperview = _inlineSuperview;

- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  if (_didResize)
    _didResize();
}

- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  if (_didResize)
    _didResize();
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (_didResize)
    _didResize();
}

- (void)viewDidMoveToSuperview {
  [super viewDidMoveToSuperview];
  if (self.superview && self.superview != _inlineSuperview)
    self.frame = self.superview.bounds;
}
@end

@interface CrestPictureInPictureDelegate : NSObject
@property(nonatomic, copy) void (^setPlaying)(BOOL);
@property(nonatomic, copy) void (^exit)(CrestPictureInPictureBehavior);
@end

@implementation CrestPictureInPictureDelegate
@synthesize setPlaying = _setPlaying;
@synthesize exit = _exit;

- (void)pipActionPlay:(id)pictureInPicture {
  if (_setPlaying)
    _setPlaying(YES);
}

- (void)pipActionPause:(id)pictureInPicture {
  if (_setPlaying)
    _setPlaying(NO);
}

- (BOOL)pipShouldClose:(id)pictureInPicture {
  if (!_exit)
    return YES;
  _exit(CrestPictureInPictureBehavior::kCloseWindowAndFocusOpener);
  return NO;
}

- (void)pipActionStop:(id)pictureInPicture {
  if (_exit)
    _exit(CrestPictureInPictureBehavior::kCloseWindowAndPauseVideo);
}

- (void)pipDidClose:(id)pictureInPicture {
  if (_exit)
    _exit(CrestPictureInPictureBehavior::kCloseWindowAndPauseVideo);
}
@end

namespace crest {
namespace {

// Blink draws WebVTT outside the video FrameSink. Read only the visible cues
// of the PiP element in its own document, including for a cross-origin frame.
constexpr char16_t kReadActiveCaptionCues[] = uR"JS(
  (() => {
    // Each tree retargets the PiP element to its nearest shadow host.
    let video = document.pictureInPictureElement;
    while (video && !(video instanceof HTMLVideoElement))
      video = video.shadowRoot?.pictureInPictureElement;
    if (!video) return '';
    const cues = [];
    let remaining = 1024;
    for (const track of video.textTracks) {
      if (track.mode !== 'showing' ||
          (track.kind !== 'captions' && track.kind !== 'subtitles')) continue;
      for (const cue of track.activeCues ?? []) {
        if (!(cue instanceof VTTCue)) continue;
        const text = cue.getCueAsHTML().textContent.trim().slice(0, remaining);
        if (!text) continue;
        cues.push(text);
        remaining -= text.length + 1;
        if (remaining <= 0) return cues.join('\n');
      }
    }
    return cues.join('\n');
  })()
)JS";

Class SystemPictureInPictureController() {
  static Class controller = []() -> Class {
    if (!dlopen(
            "/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP",
            RTLD_LAZY | RTLD_LOCAL)) {
      return Nil;
    }
    Class candidate = NSClassFromString(@"PIPViewController");
    SEL selectors[] = {
      @selector(setDelegate:),
      @selector(setAspectRatio:),
      @selector(setUserCanResize:),
      @selector(setPlaying:),
      @selector(presentViewControllerAsPictureInPicture:),
      @selector(dismissViewController:)
    };
    for (SEL selector : selectors) {
      if (![candidate instancesRespondToSelector:selector])
        return Nil;
    }
    return candidate;
  }();
  return controller;
}

// The renderer continues playing the same HTMLVideoElement. Viz embeds its
// video FrameSink in an independent compositor whose output is hosted by the
// system PiP view, including when the source tab's view is detached.
class SystemVideoPictureInPictureWindow final
    : public content::VideoOverlayWindow,
      public ui::AcceleratedWidgetMacNSView {
 public:
  explicit SystemVideoPictureInPictureWindow(
      content::VideoPictureInPictureWindowController* controller)
      : controller_(controller), compositor_(content::GetContextFactory()) {
    video_.SetFallbackBackgroundColor(SkColors::kBlack);
    compositor_.compositor()->SetRootLayer(&video_);
    compositor_.widget()->SetNSView(this);
  }

  ~SystemVideoPictureInPictureWindow() override {
    Hide();
    compositor_.widget()->ResetNSView();
    compositor_.compositor()->SetRootLayer(nullptr);
  }

  bool IsActive() const override { return view_.window.isKeyWindow; }
  bool IsVisible() const override { return presenter_ != nil; }
  void Close() override { Hide(); }

  void ShowInactive() override {
    if (IsVisible())
      return;
    auto weak = weak_.GetWeakPtr();
    const gfx::Size size = InitialSize();
    view_ = [[CrestPictureInPictureVideoView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width(), size.height())];
    view_.wantsLayer = YES;
    view_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSView* video_view = [[NSView alloc] initWithFrame:view_.bounds];
    video_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    CALayer* backing_layer = [CALayer layer];
    backing_layer.backgroundColor = NSColor.blackColor.CGColor;
    // The flipped video viewport resizes with its backing layer. Attach it
    // before AppKit assigns the backing layer its initial size.
    layers_ = std::make_unique<ui::DisplayCALayerTree>(backing_layer);
    video_view.layer = backing_layer;
    video_view.wantsLayer = YES;
    [view_ addSubview:video_view];

    captions_ = [NSTextField wrappingLabelWithString:@""];
    captions_.alignment = NSTextAlignmentCenter;
    captions_.hidden = YES;
    [view_ addSubview:captions_];
    view_.didResize = ^{
      if (weak)
        weak->Resize();
    };

    source_ = [[NSViewController alloc] init];
    source_.view = view_;
    delegate_ = [[CrestPictureInPictureDelegate alloc] init];
    delegate_.setPlaying = ^(BOOL playing) {
      if (!weak)
        return;
      if (playing) {
        weak->controller_->Play();
      } else {
        weak->controller_->Pause();
      }
    };
    delegate_.exit = ^(CrestPictureInPictureBehavior behavior) {
      if (weak)
        weak->RequestExit(behavior);
    };

    presenter_ = [[SystemPictureInPictureController() alloc] init];
    [presenter_ setDelegate:delegate_];
    [presenter_ setUserCanResize:YES];
    [presenter_ setAspectRatio:NSMakeSize(natural_size_.width(),
                                         natural_size_.height())];
    [presenter_ setPlaying:is_playing_];
    AttachAtSourceVideo();
    Resize();
    compositor_.Unsuspend();
    [presenter_ presentViewControllerAsPictureInPicture:source_];
    caption_timer_.Start(
        FROM_HERE, base::Milliseconds(200),
        base::BindRepeating(&SystemVideoPictureInPictureWindow::ReadCaptions,
                            weak));
  }

  void Hide() override {
    if (!IsVisible())
      return;
    caption_timer_.Stop();
    weak_.InvalidateWeakPtrs();
    view_.didResize = nil;
    [presenter_ setDelegate:nil];
    if (!system_closing_)
      [presenter_ dismissViewController:source_];
    if (view_.inlineSuperview && view_.superview == view_.inlineSuperview)
      [view_ removeFromSuperview];
    presenter_ = nil;
    source_ = nil;
    delegate_ = nil;
    captions_ = nil;
    view_ = nil;
    layers_.reset();
    compositor_.Suspend();
    if (surface_.is_valid())
      compositor_.compositor()->RemoveChildFrameSink(surface_.frame_sink_id());
    surface_ = viz::SurfaceId();
    caption_request_pending_ = false;
    system_closing_ = false;
    exit_requested_ = false;
  }

  gfx::Rect GetBounds() override {
    if (!view_.window)
      return gfx::Rect(InitialSize());
    const NSRect view_rect = [view_ convertRect:view_.bounds toView:nil];
    return gfx::ScreenRectFromNSRect(
        [view_.window convertRectToScreen:view_rect]);
  }

  void UpdateNaturalSize(const gfx::Size& size) override {
    if (size.IsEmpty())
      return;
    natural_size_ = size;
    [presenter_ setAspectRatio:NSMakeSize(size.width(), size.height())];
  }

  void SetPlaybackState(PlaybackState state) override {
    is_playing_ = state == kPlaying;
    [presenter_ setPlaying:is_playing_];
  }

  void SetSurfaceId(const viz::SurfaceId& surface) override {
    if (surface_ != surface) {
      if (surface_.is_valid())
        compositor_.compositor()->RemoveChildFrameSink(surface_.frame_sink_id());
      if (surface.is_valid())
        compositor_.compositor()->AddChildFrameSink(surface.frame_sink_id());
      caption_request_pending_ = false;
      ++caption_generation_;
      SetCaptions(@"");
    }
    surface_ = surface;
    Resize();
  }

  // The same native controls as WebKit. Site-provided controls remain inline.
  void SetPlayPauseButtonVisibility(bool visible) override {}
  void SetSkipAdButtonVisibility(bool visible) override {}
  void SetNextTrackButtonVisibility(bool visible) override {}
  void SetPreviousTrackButtonVisibility(bool visible) override {}
  void SetHidePictureInPictureButtonVisibility(bool visible) override {}
  void SetMicrophoneMuted(bool muted) override {}
  void SetCameraState(bool on) override {}
  void SetMediaMuted(bool muted) override {}
  void SetToggleMicrophoneButtonVisibility(bool visible) override {}
  void SetToggleCameraButtonVisibility(bool visible) override {}
  void SetHangUpButtonVisibility(bool visible) override {}
  void SetNextSlideButtonVisibility(bool visible) override {}
  void SetPreviousSlideButtonVisibility(bool visible) override {}
  void SetMediaPosition(const media_session::MediaPosition& position) override {
  }
  void SetSourceTitle(const std::u16string& title) override {}
  void SetFaviconImages(
      const std::vector<media_session::MediaImage>& images) override {}
  void SetPlaybackControlsVisibility(bool visible) override {}
  void SetImmersiveVideoOptions(
      const content::ImmersiveOptions& options) override {}

 private:
  gfx::Size InitialSize() const {
    constexpr float kLongestSide = 360;
    const int longest = std::max(natural_size_.width(), natural_size_.height());
    return gfx::ScaleToCeiledSize(natural_size_, kLongestSide / longest);
  }

  void AttachAtSourceVideo() {
    NSView* page =
        controller_->GetWebContents()->GetNativeView().GetNativeNSView();
    NSView* content = page.window.contentView;
    if (!content || !page.window.isVisible || !page.window.isOnActiveSpace)
      return;
    const gfx::Rect& source = controller_->GetSourceBounds();
    const CGFloat x = NSMinX(page.bounds) + source.x();
    const CGFloat y = page.isFlipped ? NSMinY(page.bounds) + source.y()
                                    : NSMaxY(page.bounds) - source.bottom();
    const NSRect visible_source = NSIntersectionRect(
        page.visibleRect, NSMakeRect(x, y, source.width(), source.height()));
    if (NSIsEmptyRect(visible_source))
      return;

    // The system animates from the source controller's on-screen view.
    view_.inlineSuperview = content;
    view_.frame = [content convertRect:visible_source fromView:page];
    [content addSubview:view_ positioned:NSWindowAbove relativeTo:nil];
  }

  void Resize() {
    if (!view_ || !surface_.is_valid())
      return;
    LayoutCaptions();
    const NSSize bounds = view_.bounds.size;
    const gfx::Size size =
        gfx::ToRoundedSize(gfx::SizeF(bounds.width, bounds.height));
    if (size.IsEmpty())
      return;
    auto display = display::Screen::Get()->GetDisplayMatching(GetBounds());
    float scale = display.device_scale_factor();
    compositor_.UpdateSurface(gfx::ScaleToRoundedSize(size, scale), scale,
                              display.GetColorSpaces(), display.id(),
                              display.display_frequency());
    video_.SetBounds(gfx::Rect(size));
    video_.SetShowSurface(surface_, size,
                          cc::DeadlinePolicy::UseDefaultDeadline(),
                          /*stretch_content_to_fill_bounds=*/true);
    controller_->UpdateLayerBounds();
  }

  void ReadCaptions() {
    auto* frame = content::VideoPictureInPictureWindowController::GetSourceFrame(
        controller_->GetWebContents());
    if (!frame || !frame->IsActive() || !frame->IsRenderFrameLive()) {
      SetCaptions(@"");
      return;
    }
    if (caption_request_pending_)
      return;
    caption_request_pending_ = true;
    frame->ExecuteJavaScriptInIsolatedWorld(
        kReadActiveCaptionCues,
        base::BindOnce(&SystemVideoPictureInPictureWindow::UpdateCaptions,
                       weak_.GetWeakPtr(), caption_generation_,
                       frame->GetWeakDocumentPtr()),
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }

  void UpdateCaptions(unsigned int generation,
                      content::WeakDocumentPtr document,
                      base::Value result) {
    if (generation != caption_generation_)
      return;
    caption_request_pending_ = false;
    auto* frame = document.AsRenderFrameHostIfValid();
    if (!frame ||
        frame != content::VideoPictureInPictureWindowController::GetSourceFrame(
                     controller_->GetWebContents())) {
      SetCaptions(@"");
      return;
    }
    const auto* text = result.GetIfString();
    SetCaptions(text ? base::SysUTF8ToNSString(*text) : @"");
  }

  void SetCaptions(NSString* text) {
    if (!captions_ || [captions_.stringValue isEqualToString:text])
      return;
    captions_.stringValue = text;
    captions_.hidden = text.length == 0;
    LayoutCaptions();
  }

  void LayoutCaptions() {
    if (!captions_ || captions_.hidden)
      return;
    constexpr auto domain = kMACaptionAppearanceDomainUser;
    const NSSize video_size = view_.bounds.size;
    const CGFloat scale =
        MACaptionAppearanceGetRelativeCharacterSize(domain, nullptr);
    const CGFloat font_size =
        std::max(12.0, video_size.height * 0.055) * (scale > 0 ? scale : 1);
    captions_.font = [NSFont systemFontOfSize:font_size];
    base::apple::ScopedCFTypeRef<CGColorRef> foreground(
        MACaptionAppearanceCopyForegroundColor(domain, nullptr));
    base::apple::ScopedCFTypeRef<CGColorRef> background(
        MACaptionAppearanceCopyBackgroundColor(domain, nullptr));
    NSColor* text_color =
        foreground ? [NSColor colorWithCGColor:foreground.get()] : nil;
    NSColor* background_color =
        background ? [NSColor colorWithCGColor:background.get()] : nil;
    const CGFloat text_opacity =
        MACaptionAppearanceGetForegroundOpacity(domain, nullptr);
    const CGFloat background_opacity =
        MACaptionAppearanceGetBackgroundOpacity(domain, nullptr);
    captions_.textColor = [text_color colorWithAlphaComponent:text_opacity]
                              ?: NSColor.whiteColor;
    captions_.drawsBackground = YES;
    captions_.backgroundColor =
        [background_color colorWithAlphaComponent:background_opacity]
            ?: [NSColor colorWithWhite:0 alpha:0.8];
    const NSSize available =
        NSMakeSize(video_size.width * 0.9, video_size.height * 0.65);
    const NSSize fit = [captions_ sizeThatFits:available];
    const CGFloat width = std::min(available.width, fit.width + 12);
    const CGFloat height = std::min(available.height, fit.height + 4);
    captions_.frame = NSMakeRect((video_size.width - width) * 0.5,
                                 video_size.height * 0.09, width, height);
  }

  void AcceleratedWidgetCALayerParamsUpdated(
      gfx::CALayerParams params) override {
    if (layers_)
      layers_->UpdateCALayerTree(std::move(params));
  }

  void RequestExit(CrestPictureInPictureBehavior behavior) {
    if (behavior != CrestPictureInPictureBehavior::kCloseWindowAndFocusOpener)
      system_closing_ = true;
    // Capture the first intent if the system reports both Stop and DidClose.
    if (exit_requested_)
      return;
    exit_requested_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&SystemVideoPictureInPictureWindow::Exit,
                                  weak_.GetWeakPtr(), behavior));
  }

  void Exit(CrestPictureInPictureBehavior behavior) {
    exit_requested_ = false;
    auto* manager = PictureInPictureWindowManager::GetInstance();
    if (manager->GetWebContents() == controller_->GetWebContents())
      manager->ExitPictureInPictureViaWindowUi(behavior);
  }

  raw_ptr<content::VideoPictureInPictureWindowController> controller_;
  ui::LayerSurface video_;
  ui::RecyclableCompositorMac compositor_;
  viz::SurfaceId surface_;
  gfx::Size natural_size_{320, 180};
  bool is_playing_ = false;
  bool system_closing_ = false;
  bool exit_requested_ = false;
  bool caption_request_pending_ = false;
  unsigned int caption_generation_ = 0;
  base::RepeatingTimer caption_timer_;
  CrestPictureInPictureVideoView* __strong view_ = nil;
  NSViewController* __strong source_ = nil;
  CrestPictureInPictureDelegate* __strong delegate_ = nil;
  NSViewController<CrestSystemVideoPictureInPicture>* __strong presenter_ = nil;
  NSTextField* __strong captions_ = nil;
  std::unique_ptr<ui::DisplayCALayerTree> layers_;
  base::WeakPtrFactory<SystemVideoPictureInPictureWindow> weak_{this};
};

}  // namespace

bool SupportsSystemVideoPictureInPicture() {
  return SystemPictureInPictureController() != Nil;
}

std::unique_ptr<content::VideoOverlayWindow> CreateSystemVideoPictureInPicture(
    content::VideoPictureInPictureWindowController* controller) {
  return std::make_unique<SystemVideoPictureInPictureWindow>(controller);
}

}  // namespace crest
