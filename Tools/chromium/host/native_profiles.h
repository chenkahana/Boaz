#ifndef BOAZ_CHROMIUM_NATIVE_PROFILES_H_
#define BOAZ_CHROMIUM_NATIVE_PROFILES_H_
#include <memory>
#include <string>
#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "boaz_host.h"
#include "native_downloads.h"
#include "native_cache_clearer.h"
class Profile;
namespace boaz {
class AdblockProfileState;
class NativeProfiles {
 public:
  NativeProfiles(base::FilePath user_data_root, Profile* primary);
  ~NativeProfiles();
  void Acquire(std::string identifier, bool is_private,
               base::OnceCallback<void(BoazHostResult, BoazHostProfile)> completion);
  Profile* Resolve(BoazHostProfile handle) const;
  std::shared_ptr<AdblockProfileState> Blocking(BoazHostProfile handle) const;
  bool Owns(Profile* profile) const;
  BoazHostProfile HandleFor(Profile* profile) const;
  BoazHostResult Release(BoazHostProfile handle);
  BoazHostResult ClearCache(BoazHostProfile handle, NativeCacheClearer::Completion completion);
  NativeDownloads* Downloads(BoazHostProfile handle) const;
  using DownloadObserver = base::RepeatingCallback<void(BoazHostProfile, NativeDownloads::Snapshot)>;
  void SetDownloadObserver(DownloadObserver observer);
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
#endif
