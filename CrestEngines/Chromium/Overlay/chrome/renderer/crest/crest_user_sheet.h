#ifndef CHROME_RENDERER_CREST_CREST_USER_SHEET_H_
#define CHROME_RENDERER_CREST_CREST_USER_SHEET_H_

#include <cstdint>
#include <string>

#include "base/memory/weak_ptr.h"
#include "content/public/renderer/render_frame_observer.h"
#include "v8/include/v8-forward.h"

namespace crest {

// Gives Crest's content bridge, in its own world in each of a frame's
// documents, `__crestUserSheet.insert(css)`, which adds `css` to the document
// as a user style sheet. Unlike a sheet the bridge adopts, the page's scripts
// can't list or read it, and its important rules win over the page's own,
// inline styles included, so a page can neither learn which hiding rules
// matched it nor undo them. No other world, the page's own included, gets it.
class UserSheet final : public content::RenderFrameObserver {
 public:
  explicit UserSheet(content::RenderFrame* frame);
  UserSheet(const UserSheet&) = delete;
  UserSheet& operator=(const UserSheet&) = delete;
  ~UserSheet() override;

 private:
  // content::RenderFrameObserver:
  void DidCreateScriptContext(v8::Local<v8::Context> context, int32_t world_id) override;
  void OnDestruct() override;

  // Adds `css` to the frame's current document as a user style sheet.
  void Insert(const std::string& css);

  base::WeakPtrFactory<UserSheet> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_RENDERER_CREST_CREST_USER_SHEET_H_
