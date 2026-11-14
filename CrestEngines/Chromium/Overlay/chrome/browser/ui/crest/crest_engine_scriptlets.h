#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_SCRIPTLETS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_SCRIPTLETS_H_

#include <string>

namespace content {
class NavigationHandle;
}  // namespace content

namespace crest {

// Gives the document a Crest page's main frame is about to commit the content
// filter's scriptlets for its site, `source`, to run in the page's own world
// before the page's scripts, in place of what the frame's previous document
// ran; none when `source` is empty. The frame's renderer keeps the script and
// runs it as the document starts. It goes on the frame's own channel, ahead of
// the commit, so no document of the frame starts before it arrives.
void UseScriptlets(content::NavigationHandle* navigation, const std::string& source);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_SCRIPTLETS_H_
