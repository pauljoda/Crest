#include "chrome/browser/ui/crest/crest_engine_media.h"

#include <algorithm>
#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/browser/web_contents.h"
#include "services/media_session/public/cpp/media_image_manager.h"
#include "services/media_session/public/cpp/media_metadata.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/codec/png_codec.h"

namespace crest {

namespace {

// The longest document identity Crest issues.
constexpr size_t kDocumentLength = 128;

// The longest side of the artwork Crest keeps, in pixels: what the engine's own
// media controls ask for, and enough for the system's Now Playing. The engine
// scales a larger image down to it, keeping its shape.
constexpr int kArtworkPixels = 512;

// The smallest artwork Crest takes. Any image the page gives beats none.
constexpr int kArtworkMinimumPixels = 0;

std::optional<std::string> Text(const std::u16string& value) {
  return value.empty() ? std::nullopt : std::optional<std::string>(base::UTF16ToUTF8(value));
}

}  // namespace

PageMedia::PageMedia(content::WebContents* contents, const engine::Guid& page, Present present,
                     base::RepeatingClosure changed)
    : contents_(contents), page_(page), present_(std::move(present)), changed_(std::move(changed)) {
  if (auto* session = content::MediaSession::Get(contents)) {
    session->AddObserver(receiver_.BindNewPipeAndPassRemote());
  }
}

PageMedia::~PageMedia() = default;

engine::PageMediaActivity PageMedia::Activity() const {
  using engine::PageMediaActivity;
  PageMediaActivity activity = PageMediaActivity::kNone;
  if (played_before_hidden_ || !playing_videos_.empty() || last_playing_ || contents_->IsCurrentlyAudible() ||
      contents_->GetCurrentlyPlayingVideoCount() > 0) {
    activity = activity | PageMediaActivity::kPlaying;
  }
  auto indicator = MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator();
  if (shares_ > 0 || sharing_ > 0 || contents_->IsBeingCaptured() || indicator->IsCapturingUserMedia(contents_) ||
      indicator->IsCapturingTab(contents_) || indicator->IsCapturingWindow(contents_) ||
      indicator->IsCapturingDisplay(contents_)) {
    activity = activity | PageMediaActivity::kCapturing;
  }
  if (contents_->HasPictureInPictureVideo() || contents_->HasPictureInPictureDocument()) {
    activity = activity | PageMediaActivity::kPictureInPicture;
  }
  return activity;
}

void PageMedia::PlayerStarted(const content::MediaPlayerId& id, bool has_video) {
  if (has_video) {
    playing_videos_.insert(id);
  }
}

void PageMedia::PlayerStopped(const content::MediaPlayerId& id) {
  playing_videos_.erase(id);
}

void PageMedia::AudioChanged() {
  Publish();
}

void PageMedia::DocumentChanged() {
  document_.clear();
  seen_active_ = false;
  last_playing_ = false;
  playing_videos_.clear();
  played_before_hidden_ = false;
}

void PageMedia::VisibilityChanged(bool visible) {
  played_before_hidden_ = !visible && !playing_videos_.empty();
}

void PageMedia::PictureInPictureChanged(bool active) {
  if (active || leaving_picture_in_picture_) {
    return;
  }
  leaving_picture_in_picture_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<PageMedia> media) {
                       if (media) {
                         media->leaving_picture_in_picture_ = false;
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

void PageMedia::SharedChanged(bool shared) {
  // A page the engine followed anew after the sharing began has no share
  // of it to end.
  shares_ = std::max(0, shares_ + (shared ? 1 : -1));
  changed_.Run();
}

void PageMedia::SharingChanged(bool sharing) {
  sharing_ = std::max(0, sharing_ + (sharing ? 1 : -1));
  changed_.Run();
}

// A video's return control closes its window and then asks for the page, in
// one task; a document's asks while its window is still open. An ask for a
// page whose video still floats is someone else's, such as an extension
// focusing the window.
bool PageMedia::ReturnsFromPictureInPicture() const {
  return leaving_picture_in_picture_ || contents_->HasPictureInPictureDocument();
}

// The browser's Media Session chooses the active video player and asks its
// renderer to enter Picture in Picture; no page gesture is synthesized.
bool PageMedia::EnterPictureInPicture() {
  if ((!played_before_hidden_ && playing_videos_.empty() && !last_playing_ &&
       contents_->GetCurrentlyPlayingVideoCount() == 0) ||
      contents_->HasPictureInPictureVideo() || contents_->HasPictureInPictureDocument()) {
    return false;
  }
  auto* session = content::MediaSession::GetIfExists(contents_);
  if (!session) {
    return false;
  }
  session->EnterPictureInPicture();
  return true;
}

// The window belongs to the page's video Picture in Picture controller, which
// hands the text to the window it shows. A document Picture in Picture window
// is the page's own and shows its own captions.
bool PageMedia::ShowPictureInPictureCaption(const std::string& caption) {
  if (!contents_->HasPictureInPictureVideo()) {
    return false;
  }
  content::PictureInPictureWindowController::GetOrCreateVideoPictureInPictureController(contents_)->SetCaption(
      base::UTF8ToUTF16(caption));
  return true;
}

// The engine's window manager closes the Picture in Picture window, and the
// video goes back to its element and keeps playing. It keeps one window for
// every page, so the page asks only while that window is its own.
bool PageMedia::ExitPictureInPicture() {
  if (!contents_->HasPictureInPictureVideo() && !contents_->HasPictureInPictureDocument()) {
    return false;
  }
  content::MediaSession::Get(contents_)->ExitPictureInPicture();
  return true;
}

bool PageMedia::Activate(const std::string& document) {
  if (document.empty() || document.size() > kDocumentLength) {
    return false;
  }
  document_ = document;
  Publish();
  return true;
}

bool PageMedia::Perform(const std::string& document, engine::MediaSessionAction action) {
  if (document.empty() || document != document_) {
    return false;
  }
  auto* session = content::MediaSession::Get(contents_);
  if (!session) {
    return false;
  }
  using SuspendType = media_session::mojom::MediaSession::SuspendType;
  switch (action) {
    case engine::MediaSessionAction::kPlay:
      session->Resume(SuspendType::kUI);
      break;
    case engine::MediaSessionAction::kPause:
      session->Suspend(SuspendType::kUI);
      break;
    case engine::MediaSessionAction::kPreviousTrack:
      session->PreviousTrack();
      break;
    case engine::MediaSessionAction::kNextTrack:
      session->NextTrack();
      break;
  }
  return true;
}

bool PageMedia::Mute(const std::string& document, bool muted) {
  if (document.empty() || document != document_) {
    return false;
  }
  contents_->SetAudioMuted(muted);
  return true;
}

void PageMedia::MediaSessionInfoChanged(media_session::mojom::MediaSessionInfoPtr info) {
  info_ = std::move(info);
  Publish();
}

void PageMedia::MediaSessionMetadataChanged(const std::optional<media_session::MediaMetadata>& metadata) {
  metadata_ = metadata;
  Publish();
}

void PageMedia::MediaSessionActionsChanged(const std::vector<media_session::mojom::MediaSessionAction>& actions) {
  actions_ = actions;
  Publish();
}

// The page named its artwork. The engine picks the image that best fits the
// size Crest keeps and fetches it; until it arrives the session shows none.
void PageMedia::MediaSessionImagesChanged(
    const base::flat_map<media_session::mojom::MediaSessionImageType, std::vector<media_session::MediaImage>>&
        images) {
  std::optional<media_session::MediaImage> picked;
  if (auto artwork = images.find(media_session::mojom::MediaSessionImageType::kArtwork); artwork != images.end()) {
    picked = media_session::MediaImageManager(kArtworkMinimumPixels, kArtworkPixels).SelectImage(artwork->second);
  }
  if (picked == artwork_image_) {
    return;
  }
  artwork_image_ = std::move(picked);
  ++artwork_generation_;
  const bool showed_artwork = artwork_.has_value();
  artwork_.reset();
  if (artwork_image_) {
    if (auto* session = content::MediaSession::GetIfExists(contents_)) {
      session->GetMediaImageBitmap(
          *artwork_image_, kArtworkMinimumPixels, kArtworkPixels,
          base::BindOnce(&PageMedia::ArtworkLoaded, weak_factory_.GetWeakPtr(), artwork_generation_));
    }
  }
  if (showed_artwork) {
    Publish();
  }
}

void PageMedia::ArtworkLoaded(uint64_t generation, const SkBitmap& bitmap) {
  if (generation != artwork_generation_ || bitmap.drawsNothing()) {
    return;
  }
  artwork_ = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, /*discard_transparency=*/false);
  if (artwork_) {
    Publish();
  }
}

void PageMedia::MediaSessionPositionChanged(const std::optional<media_session::MediaPosition>&) {}

void PageMedia::Publish() {
  changed_.Run();
  if (document_.empty()) {
    return;
  }
  using SessionState = media_session::mojom::MediaSessionInfo::SessionState;
  const bool engine_active = info_ && info_->state != SessionState::kInactive;
  if (engine_active) {
    seen_active_ = true;
    last_playing_ = info_->playback_state == media_session::mojom::MediaPlaybackState::kPlaying;
  }
  const bool active = engine_active || (info_ && seen_active_ && contents_->IsAudioMuted());
  engine::MediaSessionChanged session{
      .page_id = page_,
      .document = document_,
      .sequence = ++sequence_,
      .location = PresentedURL(contents_->GetLastCommittedURL()),
      .active = active,
      // While muted the engine reports no playback; the last state it did
      // report stands.
      .playback = !active        ? engine::MediaPlayback::kNone
                  : last_playing_ ? engine::MediaPlayback::kPlaying
                                  : engine::MediaPlayback::kPaused,
      .audible = contents_->IsCurrentlyAudible(),
      .muted = contents_->IsAudioMuted(),
  };
  if (metadata_) {
    session.title = Text(metadata_->title);
    session.artist = Text(metadata_->artist);
    session.album = Text(metadata_->album);
  }
  session.artwork = artwork_;
  for (auto action : actions_) {
    switch (action) {
      case media_session::mojom::MediaSessionAction::kPlay:
        session.actions.push_back(engine::MediaSessionAction::kPlay);
        break;
      case media_session::mojom::MediaSessionAction::kPause:
        session.actions.push_back(engine::MediaSessionAction::kPause);
        break;
      case media_session::mojom::MediaSessionAction::kPreviousTrack:
        session.actions.push_back(engine::MediaSessionAction::kPreviousTrack);
        break;
      case media_session::mojom::MediaSessionAction::kNextTrack:
        session.actions.push_back(engine::MediaSessionAction::kNextTrack);
        break;
      default:
        break;
    }
  }
  present_.Run(std::move(session));
}

}  // namespace crest
