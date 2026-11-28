#include "chrome/browser/ui/crest/crest_desktop_default_browser.h"

#include <windows.h>

#include <string>

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/path_service.h"
#include "base/task/single_thread_task_runner.h"
#include "base/task/task_traits.h"
#include "base/task/thread_pool.h"
#include "base/win/default_apps_util.h"
#include "base/win/registry.h"
#include "chrome/install_static/install_util.h"
#include "chrome/installer/util/shell_util.h"

namespace crest {

namespace {

// The name Crest is registered with Windows by: its install mode's base app
// name, with the suffix Chromium finds its registration under, which Setup
// leaves empty.
std::wstring RegisteredName(const base::FilePath& chrome_exe) {
  return install_static::GetBaseAppName() + ShellUtil::GetCurrentInstallationSuffix(chrome_exe);
}

// Whether Windows' Default apps lists Crest as a browser, for this person
// or for every one on the device.
bool IsRegistered(const std::wstring& name) {
  for (HKEY root : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
    base::win::RegKey key(root, ShellUtil::kRegRegisteredApplications, KEY_QUERY_VALUE);
    if (key.Valid() && key.HasValue(name.c_str())) return true;
  }
  return false;
}

DefaultBrowserState ReadDefaultBrowser() {
  base::FilePath chrome_exe;
  if (!base::PathService::Get(base::FILE_EXE, &chrome_exe)) return DefaultBrowserState::kUnknown;
  if (!IsRegistered(RegisteredName(chrome_exe))) return DefaultBrowserState::kUnregistered;
  switch (ShellUtil::GetChromeDefaultState()) {
    case ShellUtil::IS_DEFAULT:
      return DefaultBrowserState::kIsDefault;
    case ShellUtil::NOT_DEFAULT:
    case ShellUtil::OTHER_MODE_IS_DEFAULT:
      return DefaultBrowserState::kNotDefault;
    default:
      return DefaultBrowserState::kUnknown;
  }
}

bool LaunchDefaultApps() {
  base::FilePath chrome_exe;
  if (!base::PathService::Get(base::FILE_EXE, &chrome_exe)) return false;
  // Windows 11 opens on Crest's own page, whose Set default makes Crest the
  // browser; Windows 10 opens Default apps, whose Web browser the person
  // picks Crest for.
  return base::win::LaunchSettingsDefaultApps(RegisteredName(chrome_exe), !install_static::IsSystemInstall()) ||
         base::win::LaunchDefaultAppsSettingsModernDialog(L"http");
}

// Windows' associations are COM, which runs on a thread of its own.
scoped_refptr<base::SingleThreadTaskRunner> ComRunner() {
  return base::ThreadPool::CreateCOMSTATaskRunner({base::MayBlock(), base::TaskPriority::USER_VISIBLE});
}

}  // namespace

std::string_view DefaultBrowserStateName(DefaultBrowserState state) {
  switch (state) {
    case DefaultBrowserState::kIsDefault:
      return "isDefault";
    case DefaultBrowserState::kNotDefault:
      return "notDefault";
    case DefaultBrowserState::kUnregistered:
      return "unregistered";
    case DefaultBrowserState::kUnknown:
      return "unknown";
  }
  return "unknown";
}

void CheckDefaultBrowser(base::OnceCallback<void(DefaultBrowserState)> done) {
  ComRunner()->PostTaskAndReplyWithResult(FROM_HERE, base::BindOnce(&ReadDefaultBrowser), std::move(done));
}

void OpenDefaultAppsSettings(base::OnceCallback<void(bool)> done) {
  ComRunner()->PostTaskAndReplyWithResult(FROM_HERE, base::BindOnce(&LaunchDefaultApps), std::move(done));
}

}  // namespace crest
