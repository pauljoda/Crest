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
void EnsureCrestUIStarted(Browser* browser);
// Chrome's AppController retains its lifecycle role. A quit waits for core saves.
bool DeferQuit();
// Consumes the result of a native close preflight without destroying the page.
bool CompletePageClosePreparation(content::WebContents* contents, bool proceed);
// Called after Chromium has approved a renderer's drag request.
bool BeginLinkDrag(content::WebContents* contents, const content::DropData& data);
void AddNavigationThrottle(content::NavigationThrottleRegistry& registry);
// Applies semantic policy after Chromium validates a renderer's original request.
bool RouteModifiedLink(content::WebContents* source, content::OpenURLParams& params);
#ifdef __OBJC__
NSWindow* WindowForBrowser(Browser* browser);
void AppendLinkMenuItem(NSMenu* menu, content::WebContents* contents, const GURL& url);
#endif
}  // namespace crest

#endif
