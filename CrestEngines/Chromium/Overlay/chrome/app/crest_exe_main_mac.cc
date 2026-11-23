// Copyright 2026 The Crest Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The browser app's own executable: what Finder, the Dock, a login item, the
// default-browser role and an update's relaunch start.
//
// Upstream builds this executable from chrome_exe_main_mac.c, which links the
// Chromium framework and calls ChromeMain before anything else can run. Crest
// decides three things first, so `chrome_app` builds from this file instead:
//
//   * a packaged experiment refuses to start without an explicit profile
//     folder and its host mode;
//   * a product bundle names its own engine profile folder,
//     ~/Library/Application Support/Crest/Chromium, and adopts the profiles an
//     earlier build left in Chromium's default folder, before any is read;
//   * Crest's native host owns AppKit and its core first, and the framework
//     loads only once a page or an engine feature needs Chromium.
//
// The browser process needs nothing from Apéritif, which engages the helpers'
// sandbox before their system libraries start; the helpers keep upstream's
// entry points. The engine build and packaging refuse a browser executable
// that lacks `kLaunchSentinel` or links the framework.

#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "base/allocator/early_zone_registration_apple.h"
#include "base/compiler_specific.h"
#include "chrome/app/crest_user_data_dir.h"
#include "chrome/common/chrome_version.h"

extern "C" {
// abort_report_np() records the message in a special section that both the
// system CrashReporter and Crashpad collect in crash reports.
void abort_report_np(const char* fmt, ...);
}

namespace {

// Scripts/control-plane/chromium_fork.py looks for this in every architecture
// of the browser executable. Keep the two spellings identical.
__attribute__((used)) constexpr char kLaunchSentinel[] = "crest-browser-launch";

[[clang::not_tail_called]] [[noreturn]] void FatalError(const char* format,
                                                        ...) {
  va_list valist;
  va_start(valist, format);
  char message[4096];
  if (UNSAFE_TODO(vsnprintf(message, sizeof(message), format, valist)) >= 0) {
    UNSAFE_TODO(fputs(message, stderr));
    abort_report_np("%s", message);
  }
  va_end(valist);
  abort();
}

}  // namespace

__attribute__((visibility("default"))) int main(int argc, char* argv[]) {
  partition_alloc::EarlyMallocZoneRegistration();

  uint32_t exec_path_size = 0;
  int rv = _NSGetExecutablePath(NULL, &exec_path_size);
  if (rv != -1) {
    FatalError("_NSGetExecutablePath: get length failed.");
  }

  std::unique_ptr<char[]> exec_path(new char[exec_path_size]);
  rv = _NSGetExecutablePath(exec_path.get(), &exec_path_size);
  if (rv != 0) {
    FatalError("_NSGetExecutablePath: get path failed.");
  }

  const std::string executable(exec_path.get());
  const auto directory = executable.substr(0, executable.find_last_of('/'));
  bool named_profile_root = false;
  bool crest_host = false;
  for (int i = 1; i < argc; ++i) {
    const std::string_view argument(UNSAFE_TODO(argv[i]));
    if (argument.starts_with("--user-data-dir=/") &&
        argument.size() > std::string_view("--user-data-dir=/").size()) {
      named_profile_root = true;
    }
    crest_host |= argument == "--crest-control-plane";
  }

  // Packaged Crest experiments must never fall back to Chromium's default
  // user profile when Finder or an automation tool launches without arguments.
  // This runs before loading the framework or creating any browser services.
  const auto marker = directory + "/../Resources/Crest-Isolated-Experiment";
  if (access(marker.c_str(), F_OK) == 0) {
    const auto host_framework =
        directory + "/../Frameworks/CrestChromiumUI.framework";
    if (!named_profile_root ||
        (access(host_framework.c_str(), F_OK) == 0 && !crest_host)) {
      fprintf(stderr, "Crest experiment requires an explicit absolute "
                      "--user-data-dir and its host mode.\n");
      return 64;
    }
  }

  // A product bundle is launched with no switches at all, so it names its own
  // engine profile root here instead of opening the directory every other
  // Chromium on this machine also opens by default. Adoption of the engine
  // profiles an earlier build left there happens in the same step, before the
  // framework is loaded and therefore before any profile is read.
  std::string product_user_data_switch;
  std::vector<char*> product_argv;
  const auto product_marker = directory + "/../Resources/Crest-Native-Host";
  const char* home = getenv("HOME");
  if (!named_profile_root && home && *home &&
      access(product_marker.c_str(), F_OK) == 0) {
    product_user_data_switch =
        "--user-data-dir=" + crest::AdoptProductUserDataDirectory(home);
    for (int i = 0; i < argc; ++i) {
      product_argv.push_back(UNSAFE_TODO(argv[i]));
    }
    product_argv.push_back(product_user_data_switch.data());
    product_argv.push_back(nullptr);
    argc = static_cast<int>(product_argv.size()) - 1;
    argv = product_argv.data();
  }

  // Crest owns AppKit and its core before Chromium is needed. Its launch loop
  // returns one only when a page or an explicit engine feature needs Chromium;
  // WebKit-only browsing never loads the Chromium framework below.
  std::vector<char*> native_argv;
  std::string native_switch = "--crest-app-owned-host";
  if (access((directory + "/../Resources/Crest-App-Owned-Host").c_str(),
             F_OK) == 0) {
    void* ui = nullptr;
    for (const char* name : {"CrestChromiumUI", "CrestChromiumUIProduct"}) {
      const std::string path =
          directory + "/../Frameworks/" + name + ".framework/" + name;
      if (access(path.c_str(), F_OK) != 0) {
        continue;
      }
      ui = dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST);
      if (!ui) {
        FatalError("dlopen %s: %s.", path.c_str(), dlerror());
      }
      break;
    }
    if (!ui) {
      FatalError("Crest's native host framework is missing.");
    }
    using NativeHostRun = int (*)();
    const auto run =
        reinterpret_cast<NativeHostRun>(dlsym(ui, "crest_native_host_run"));
    if (!run) {
      FatalError("Crest's native host entry point is missing: %s.", dlerror());
    }
    if (run() != 1) {
      return 0;
    }
    for (int i = 0; i < argc; ++i) {
      native_argv.push_back(UNSAFE_TODO(argv[i]));
    }
    native_argv.push_back(native_switch.data());
    native_argv.push_back(nullptr);
    argc = static_cast<int>(native_argv.size()) - 1;
    argv = native_argv.data();
  }

  // The framework sits in the bundle's versioned framework directory.
  static constexpr char rel_path[] =
      "../Frameworks/" PRODUCT_FULLNAME_STRING
      " Framework.framework/Versions/" CHROME_VERSION_STRING
      "/" PRODUCT_FULLNAME_STRING " Framework";
  const char* parent_dir = dirname(exec_path.get());
  if (!parent_dir) {
    FatalError("dirname %s: %s.", exec_path.get(), strerror(errno));
  }
  const std::string framework_path = std::string(parent_dir) + "/" + rel_path;
  void* library =
      dlopen(framework_path.c_str(), RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST);
  if (!library) {
    FatalError("dlopen %s: %s.", framework_path.c_str(), dlerror());
  }

  using ChromeMainPtr = int (*)(int, const char**);
  const ChromeMainPtr chrome_main =
      reinterpret_cast<ChromeMainPtr>(dlsym(library, "ChromeMain"));
  if (!chrome_main) {
    FatalError("dlsym ChromeMain: %s.", dlerror());
  }
  rv = chrome_main(argc, const_cast<const char**>(argv));

  // exit, don't return from main, to avoid the apparent removal of main from
  // stack backtraces under tail call optimization.
  exit(rv);
}
