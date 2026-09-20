#ifndef CHROME_BROWSER_UI_CREST_CREST_PERMISSION_PROMPT_H_
#define CHROME_BROWSER_UI_CREST_CREST_PERMISSION_PROMPT_H_
#include "components/permissions/permission_prompt.h"
namespace crest {
std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* contents, permissions::PermissionPrompt::Delegate* delegate);
}
#endif
