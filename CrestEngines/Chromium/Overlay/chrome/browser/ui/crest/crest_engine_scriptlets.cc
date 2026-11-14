#include "chrome/browser/ui/crest/crest_engine_scriptlets.h"

#include <utility>

#include "base/strings/utf_string_conversions.h"
#include "components/js_injection/common/interfaces.mojom.h"
#include "components/origin_matcher/origin_matcher.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/common/isolated_world_ids.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"

namespace crest {

namespace {

// The one script a frame keeps for the content filter, replaced as the frame
// goes to another site.
constexpr int32_t kScriptletsID = 1;

}  // namespace

void UseScriptlets(content::NavigationHandle* navigation, const std::string& source) {
  content::RenderFrameHost* frame = navigation->GetRenderFrameHost();
  if (!frame || !frame->IsRenderFrameLive()) {
    return;
  }
  mojo::AssociatedRemote<js_injection::mojom::JsCommunication> renderer;
  frame->GetRemoteAssociatedInterfaces()->GetInterface(&renderer);
  renderer->RemovePersistentJavaScript(kScriptletsID);
  if (source.empty()) {
    return;
  }
  // The frame runs it for whichever document commits next, which is this one.
  origin_matcher::OriginMatcher every_origin;
  every_origin.AddRuleFromString("*");
  renderer->AddPersistentJavaScript(js_injection::mojom::JavaScriptExecutable::New(
      kScriptletsID, base::UTF8ToUTF16(source), std::move(every_origin),
      js_injection::mojom::DocumentInjectionTime::kDocumentStart, content::ISOLATED_WORLD_ID_GLOBAL));
}

}  // namespace crest
