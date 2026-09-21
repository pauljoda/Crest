#ifndef CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_
#define CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#endif

class Browser;
class GURL;
namespace content { class WebContents; class NavigationThrottleRegistry; struct DropData; struct OpenURLParams; }

namespace crest {
// Enabled only by the explicitly selected Crest host command-line switch.
bool IsEnabled();
void OnBrowserWindowCreated(Browser* browser);
void OnBrowserWindowDestroyed(Browser* browser);
// A Browser the engine created for itself was shown. Crest opens the window it
// reserved for that Browser when the Browser's first tab is offered, so this
// only records whether `chrome.windows.create` asked for focus.
void OnEngineWindowShown(Browser* browser, bool focused);
void EnsureCrestUIStarted(Browser* browser);
// Chrome's AppController retains its lifecycle role. A quit waits for core saves.
bool DeferQuit();
// A Dock click or reopen with no windows. Crest activates an existing window
// or opens its initial one; Chromium creates no browser of its own.
bool Reopen();
// Consumes the result of a native close preflight without destroying the page.
bool CompletePageClosePreparation(content::WebContents* contents, bool proceed);
// Called after Chromium has approved a renderer's drag request.
bool BeginLinkDrag(content::WebContents* contents, const content::DropData& data);
void AddNavigationThrottle(content::NavigationThrottleRegistry& registry);
// Applies semantic policy after Chromium validates a renderer's original request.
bool RouteModifiedLink(content::WebContents* source, content::OpenURLParams& params);
#ifdef __OBJC__
// Consumes an external open: a link from another app, a document, or the
// default-browser role. Crest applies its own routing policy.
bool OpenExternalURLs(NSArray<NSURL*>* urls);
NSWindow* WindowForBrowser(Browser* browser);
void AppendLinkMenuItem(NSMenu* menu, content::WebContents* contents, const GURL& url);
#endif
}  // namespace crest

#endif
