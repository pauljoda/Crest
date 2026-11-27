#ifndef CHROME_BROWSER_UI_WEBUI_CREST_COMPARISON_UI_H_
#define CHROME_BROWSER_UI_WEBUI_CREST_COMPARISON_UI_H_

#include "content/public/browser/web_ui_controller.h"

class CrestComparisonUI : public content::WebUIController {
 public:
  explicit CrestComparisonUI(content::WebUI* web_ui);
  WEB_UI_CONTROLLER_TYPE_DECL();
};

#endif
