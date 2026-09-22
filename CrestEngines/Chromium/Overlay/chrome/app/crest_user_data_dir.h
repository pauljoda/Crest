// Copyright 2025 The Crest Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_APP_CREST_USER_DATA_DIR_H_
#define CHROME_APP_CREST_USER_DATA_DIR_H_

// Chooses the engine profile root a Crest product bundle uses when it is
// launched without arguments, and adopts the engine profiles an earlier build
// left in Chromium's shared default directory.
//
// This is consumed by the browser executable's `main`, before the Chromium
// framework is loaded, so it deliberately uses only libc and libc++: no
// //base, no logging, no Objective-C runtime.

#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <sys/errno.h>
#include <sys/stat.h>
#include <unistd.h>

#include <string>
#include <vector>

namespace crest {

inline bool IsDirectory(const std::string& path) {
  struct stat info;
  return stat(path.c_str(), &info) == 0 && S_ISDIR(info.st_mode);
}

inline bool MakeDirectoryTree(const std::string& path) {
  if (IsDirectory(path)) {
    return true;
  }
  const auto separator = path.find_last_of('/');
  if (separator != std::string::npos && separator > 0 &&
      !MakeDirectoryTree(path.substr(0, separator))) {
    return false;
  }
  return mkdir(path.c_str(), 0700) == 0 || IsDirectory(path);
}

// The engine profile directories Crest creates for its own Spaces. They are the
// only state in a shared Chromium user data directory that belongs to Crest:
// `Default`, `Local State`, `Safe Browsing`, crash state and every other entry
// belongs to whichever Chromium created that directory.
inline std::vector<std::string> CrestProfileDirectories(
    const std::string& directory) {
  std::vector<std::string> names;
  DIR* handle = opendir(directory.c_str());
  if (!handle) {
    return names;
  }
  while (struct dirent* entry = readdir(handle)) {
    const std::string name(entry->d_name);
    if (name.rfind("Crest-", 0) != 0 || !IsDirectory(directory + "/" + name)) {
      continue;
    }
    names.push_back(name);
  }
  closedir(handle);
  return names;
}

// The name of the record a directory adoption leaves in the new engine profile
// root for the browser process to finish. Moving the directories is all this
// step can do: registering an adopted profile in `Local State` and retiring its
// encrypted tracked-preference validators are JSON edits, and no JSON reader
// exists this early. `crest::CompleteProfileAdoption` consumes the record.
inline const char* AdoptionRecordName() {
  return "Crest Adoption";
}

// Records which engine profiles moved and where they came from. Line one is the
// previous root; every later line is one adopted directory name. A directory
// name cannot contain a newline, so no quoting is needed.
inline void WriteAdoptionRecord(const std::string& preferred,
                                const std::string& previous,
                                const std::vector<std::string>& adopted) {
  if (adopted.empty()) {
    return;
  }
  const std::string path = preferred + "/" + AdoptionRecordName();
  FILE* file = fopen(path.c_str(), "w");
  if (!file) {
    fprintf(stderr, "Crest: cannot record adoption in %s (%s); the adopted "
                    "engine profiles stay unregistered.\n",
            path.c_str(), strerror(errno));
    return;
  }
  fprintf(file, "%s\n", previous.c_str());
  for (const std::string& name : adopted) {
    fprintf(file, "%s\n", name.c_str());
  }
  fclose(file);
}

// Returns the user data directory a product bundle should open.
//
// Crest keeps its engine state under its own application support directory
// rather than in `~/Library/Application Support/Chromium`, which every other
// Chromium on the machine — including Crest's own review and baseline packages
// — also opens by default. The first launch after that move adopts the engine
// profiles the previous default directory still holds, and nothing else.
//
// Any failure falls back to the previous directory and says so on stderr, so a
// product launch never loses the Spaces it already has.
inline std::string AdoptProductUserDataDirectory(const std::string& home) {
  const std::string support = home + "/Library/Application Support";
  const std::string preferred = support + "/Crest/Chromium";
  const std::string previous = support + "/Chromium";
  if (IsDirectory(preferred)) {
    return preferred;
  }
  const std::vector<std::string> names = CrestProfileDirectories(previous);
  if (!MakeDirectoryTree(preferred)) {
    fprintf(stderr, "Crest: cannot create %s (%s); using %s.\n",
            preferred.c_str(), strerror(errno), previous.c_str());
    return previous;
  }
  std::vector<std::string> adopted;
  for (const std::string& name : names) {
    if (rename((previous + "/" + name).c_str(),
               (preferred + "/" + name).c_str()) == 0) {
      adopted.push_back(name);
      continue;
    }
    // A partial adoption would split one Space's profiles across two roots.
    // Put back what moved and keep using the directory that still has them.
    fprintf(stderr, "Crest: cannot adopt engine profile %s (%s); using %s.\n",
            name.c_str(), strerror(errno), previous.c_str());
    for (const std::string& moved : adopted) {
      rename((preferred + "/" + moved).c_str(),
             (previous + "/" + moved).c_str());
    }
    rmdir(preferred.c_str());
    return previous;
  }
  for (const std::string& name : adopted) {
    fprintf(stderr, "Crest: adopted engine profile %s into %s.\n", name.c_str(),
            preferred.c_str());
  }
  WriteAdoptionRecord(preferred, previous, adopted);
  return preferred;
}

}  // namespace crest

#endif  // CHROME_APP_CREST_USER_DATA_DIR_H_
