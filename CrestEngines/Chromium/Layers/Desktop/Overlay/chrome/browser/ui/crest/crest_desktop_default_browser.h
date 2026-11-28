#ifndef CHROME_BROWSER_UI_CREST_CREST_DESKTOP_DEFAULT_BROWSER_H_
#define CHROME_BROWSER_UI_CREST_CREST_DESKTOP_DEFAULT_BROWSER_H_

#include <string_view>

#include "base/functional/callback_forward.h"

namespace crest {

// What Windows says about Crest as the browser links open in, as Chromium
// reads Windows' choice for http and https: Crest opens them, another
// browser does, Crest isn't registered with Windows as a browser (only Setup
// registers it), or Windows couldn't say.
enum class DefaultBrowserState {
  kIsDefault,
  kNotDefault,
  kUnregistered,
  kUnknown,
};

// The state as the interface names it.
std::string_view DefaultBrowserStateName(DefaultBrowserState state);

// Reads the state on a COM thread and answers it on the calling sequence.
void CheckDefaultBrowser(base::OnceCallback<void(DefaultBrowserState)> done);

// Opens Windows' Default apps settings on Crest's own page, the only place
// Windows lets the person make Crest their browser, and answers on the
// calling sequence whether they opened. Crest never registers itself here:
// Setup registers what Crest opens, as the Mac app declares it.
void OpenDefaultAppsSettings(base::OnceCallback<void(bool)> done);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_DESKTOP_DEFAULT_BROWSER_H_
