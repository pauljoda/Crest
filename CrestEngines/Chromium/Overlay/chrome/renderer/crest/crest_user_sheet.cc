#include "chrome/renderer/crest/crest_user_sheet.h"

#include <tuple>

#include "base/functional/bind.h"
#include "content/public/renderer/render_frame.h"
#include "gin/converter.h"
#include "gin/function_template.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_css_origin.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "v8/include/v8-context.h"
#include "v8/include/v8-function.h"
#include "v8/include/v8-isolate.h"
#include "v8/include/v8-local-handle.h"
#include "v8/include/v8-object.h"
#include "v8/include/v8-template.h"

namespace crest {

namespace {

// The isolated world Crest's content bridges run in, crest::kContentWorldID in
// chrome/browser/ui/crest/crest_chrome_hooks.h, which the renderer can't
// include.
constexpr int32_t kContentWorldID = (1 << 29) - 1;

}  // namespace

UserSheet::UserSheet(content::RenderFrame* frame) : content::RenderFrameObserver(frame) {}

UserSheet::~UserSheet() = default;

void UserSheet::DidCreateScriptContext(v8::Local<v8::Context> context, int32_t world_id) {
  if (world_id != kContentWorldID) {
    return;
  }
  v8::Isolate* isolate = render_frame()->GetWebFrame()->GetAgentGroupScheduler()->Isolate();
  v8::HandleScope handle_scope(isolate);
  v8::Context::Scope context_scope(context);
  v8::Local<v8::Function> insert;
  if (!gin::CreateFunctionTemplate(isolate, base::BindRepeating(&UserSheet::Insert, weak_factory_.GetWeakPtr()))
           ->GetFunction(context)
           .ToLocal(&insert)) {
    return;
  }
  v8::Local<v8::Object> sheet = v8::Object::New(isolate);
  if (!sheet->CreateDataProperty(context, gin::StringToSymbol(isolate, "insert"), insert).FromMaybe(false) ||
      !sheet->SetIntegrityLevel(context, v8::IntegrityLevel::kFrozen).FromMaybe(false)) {
    return;
  }
  // Fixed in place, so nothing else in the world can stand in for it.
  std::ignore = context->Global()->DefineOwnProperty(
      context, gin::StringToSymbol(isolate, "__crestUserSheet"), sheet,
      static_cast<v8::PropertyAttribute>(v8::ReadOnly | v8::DontEnum | v8::DontDelete));
}

void UserSheet::OnDestruct() {
  delete this;
}

void UserSheet::Insert(const std::string& css) {
  if (css.empty()) {
    return;
  }
  render_frame()->GetWebFrame()->GetDocument().InsertStyleSheet(blink::WebString::FromUtf8(css), nullptr,
                                                                blink::WebCssOrigin::kUser);
}

}  // namespace crest
