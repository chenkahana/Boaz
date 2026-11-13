#include "adblock_profile_state.h"
#include "native_profiles.h"
#include <limits>
#include <map>
#include <utility>
#include <vector>
#include "base/check.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/string_number_conversions.h"
#include "crypto/sha2.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_destroyer.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "content/public/browser/browser_thread.h"
namespace boaz {
class NativeProfiles::Impl {
 public:
  using Completion = base::OnceCallback<void(BoazHostResult, BoazHostProfile)>;
  struct Entry {
    raw_ptr<Profile> profile;
    std::unique_ptr<ScopedProfileKeepAlive> keep_alive;
    std::string identifier;
    bool is_private;
    std::unique_ptr<NativeDownloads> downloads;
    std::unique_ptr<NativeCacheClearer> cache_clearer;
    bool cache_pending = false;
    bool release_requested = false;
    std::shared_ptr<AdblockProfileState> blocking = std::make_shared<AdblockProfileState>();
  };
  Impl(base::FilePath root, Profile* primary) : root_(std::move(root)), primary_(primary) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK(primary_);
    CHECK(!primary_->IsOffTheRecord());
  }
  ~Impl() {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK(pending_.empty());
    weak_.InvalidateWeakPtrs();
    for (auto& [id, entry] : entries_) {
      entry.blocking->Close();
      CHECK(!entry.cache_pending);
      CHECK(!entry.cache_clearer || !entry.cache_clearer->busy());
      entry.cache_clearer.reset();
      entry.downloads.reset();
      if (entry.is_private) ProfileDestroyer::DestroyOTRProfileWhenAppropriate(entry.profile);
    }
  }
  static void Post(Completion callback, BoazHostResult result, BoazHostProfile handle = 0) {
    if (callback)
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(std::move(callback), result, handle));
  }
  bool SafeRoot() const {
    base::FilePath canonical;
    if (!root_.IsAbsolute() || !base::DirectoryExists(root_) ||
        !base::NormalizeFilePath(root_, &canonical) || canonical != root_) return false;
    for (auto path = root_;; path = path.DirName()) {
      if (base::IsLink(path)) return false;
      if (path == path.DirName()) break;
    }
    return true;
  }
  bool SafePath(const base::FilePath& path) const {
    return SafeRoot() && !base::IsLink(path) &&
        (!base::PathExists(path) || base::DirectoryExists(path));
  }
  BoazHostProfile Insert(Profile* profile, std::string identifier, bool private_session,
                         std::unique_ptr<ScopedProfileKeepAlive> keep_alive) {
    static uint64_t next = 1;
    CHECK_NE(next, std::numeric_limits<uint64_t>::max());
    auto id = next++;
    auto downloads = std::make_unique<NativeDownloads>(profile);
    downloads->SetObserver(base::BindRepeating(&Impl::DownloadChanged, weak_.GetWeakPtr(), id));
    entries_.emplace(id, Entry{profile, std::move(keep_alive), std::move(identifier),
                              private_session, std::move(downloads), nullptr});
    return id;
  }
  void Acquire(std::string identifier, bool private_session, Completion callback) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (identifier.empty() || identifier.size() > 128 ||
        identifier.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") != std::string::npos) {
      Post(std::move(callback), BOAZ_HOST_INVALID_ARGUMENT); return;
    }
    if (!SafeRoot()) { Post(std::move(callback), BOAZ_HOST_UNAVAILABLE); return; }
    if (private_session) {
      auto keep_alive = ScopedProfileKeepAlive::TryAcquire(primary_, ProfileKeepAliveOrigin::kOffTheRecordProfile);
      if (!keep_alive) { Post(std::move(callback), BOAZ_HOST_UNAVAILABLE); return; }
      auto* profile = primary_->GetOffTheRecordProfile(Profile::OTRProfileID::CreateUnique("Boaz"), true);
      if (!profile) { Post(std::move(callback), BOAZ_HOST_UNAVAILABLE); return; }
      Post(std::move(callback), BOAZ_HOST_OK,
           Insert(profile, std::move(identifier), true, std::move(keep_alive)));
      return;
    }
    for (const auto& [id, entry] : entries_) {
      if (!entry.is_private && entry.identifier == identifier) {
        Post(std::move(callback), entry.release_requested ? BOAZ_HOST_UNAVAILABLE : BOAZ_HOST_OK,
             entry.release_requested ? 0 : id); return;
      }
    }
    auto found = pending_.find(identifier);
    if (found != pending_.end()) { found->second.push_back(std::move(callback)); return; }
    const auto path = root_.AppendASCII("Boaz-" + base::HexEncode(crypto::SHA256HashString(identifier)));
    if (!SafePath(path) || !g_browser_process || !g_browser_process->profile_manager()) {
      Post(std::move(callback), BOAZ_HOST_UNAVAILABLE); return;
    }
    pending_[identifier].push_back(std::move(callback));
    g_browser_process->profile_manager()->CreateProfileAsync(path,
        base::BindOnce(&Impl::Prepared, weak_.GetWeakPtr(), identifier, path));
  }
  void Prepared(std::string identifier, base::FilePath path, Profile* profile) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = pending_.find(identifier);
    CHECK(found != pending_.end());
    auto callbacks = std::move(found->second);
    pending_.erase(found);
    BoazHostProfile handle = 0;
    if (profile && !profile->IsOffTheRecord() && profile->GetPath() == path && SafePath(path)) {
      auto keep_alive = ScopedProfileKeepAlive::TryAcquire(profile, ProfileKeepAliveOrigin::kBrowserWindow);
      if (keep_alive) handle = Insert(profile, std::move(identifier), false, std::move(keep_alive));
    }
    for (auto& callback : callbacks)
      Post(std::move(callback), handle ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE, handle);
  }
  Profile* Resolve(BoazHostProfile handle) const {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = entries_.find(handle);
    return found == entries_.end() || found->second.release_requested
        ? nullptr : found->second.profile.get();
  }
  BoazHostProfile HandleFor(Profile* profile) const {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!profile) return 0;
    for (const auto& [handle, entry] : entries_)
      if (entry.profile == profile && !entry.release_requested) return handle;
    return 0;
  }
  bool Owns(Profile* profile) const {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!profile) return false;
    for (const auto& [handle, entry] : entries_)
      if (entry.profile == profile && !entry.release_requested) return true;
    return false;
  }
  NativeDownloads* Downloads(BoazHostProfile handle) const {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = entries_.find(handle);
    return found == entries_.end() || found->second.release_requested
        ? nullptr : found->second.downloads.get();
  }
  void DownloadChanged(BoazHostProfile handle, NativeDownloads::Snapshot snapshot) {
    auto found = entries_.find(handle);
    if (found == entries_.end() || found->second.release_requested || !download_observer_) return;
    auto observer = download_observer_;
    observer.Run(handle, std::move(snapshot));
  }
  void SetDownloadObserver(DownloadObserver observer) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    download_observer_ = std::move(observer);
    for (auto& [handle, entry] : entries_)
      entry.downloads->SetObserver(base::BindRepeating(&Impl::DownloadChanged, weak_.GetWeakPtr(), handle));
  }
  BoazHostResult ClearCache(BoazHostProfile handle, NativeCacheClearer::Completion completion) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = entries_.find(handle);
    if (found == entries_.end() || found->second.release_requested) return BOAZ_HOST_INVALID_HANDLE;
    if (!completion) return BOAZ_HOST_INVALID_ARGUMENT;
    auto& entry = found->second;
    if (entry.cache_pending) return BOAZ_HOST_UNAVAILABLE;
    if (!entry.cache_clearer)
      entry.cache_clearer = std::make_unique<NativeCacheClearer>(entry.profile.get());
    entry.cache_pending = true;
    if (!entry.cache_clearer->Clear(base::BindOnce(&Impl::CacheCleared,
            weak_.GetWeakPtr(), handle, std::move(completion)))) {
      entry.cache_pending = false;
      return BOAZ_HOST_UNAVAILABLE;
    }
    return BOAZ_HOST_OK;
  }
  void CacheCleared(BoazHostProfile handle, NativeCacheClearer::Completion completion,
                    NativeCacheClearer::Result result) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = entries_.find(handle);
    CHECK(found != entries_.end());
    CHECK(found->second.cache_pending);
    found->second.cache_pending = false;
    if (found->second.release_requested) Release(handle);
    std::move(completion).Run(result);
  }
  std::shared_ptr<AdblockProfileState> Blocking(BoazHostProfile handle) const {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = entries_.find(handle);
    return found == entries_.end() || found->second.release_requested
        ? nullptr : found->second.blocking;
  }
  BoazHostResult Release(BoazHostProfile handle) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = entries_.find(handle);
    if (found == entries_.end()) return BOAZ_HOST_INVALID_HANDLE;
    found->second.blocking->Close();
    if (found->second.cache_pending) {
      found->second.release_requested = true;
      return BOAZ_HOST_OK;
    }
    auto entry = std::move(found->second);
    entries_.erase(found);
    CHECK(!entry.cache_clearer || !entry.cache_clearer->busy());
    entry.cache_clearer.reset();
    entry.downloads.reset();
    if (entry.is_private) ProfileDestroyer::DestroyOTRProfileWhenAppropriate(entry.profile);
    return BOAZ_HOST_OK;
  }
 private:
  DownloadObserver download_observer_;
  const base::FilePath root_;
  raw_ptr<Profile> primary_;
  std::map<BoazHostProfile, Entry> entries_;
  std::map<std::string, std::vector<Completion>> pending_;
  base::WeakPtrFactory<Impl> weak_{this};
};
NativeProfiles::NativeProfiles(base::FilePath root, Profile* primary)
    : impl_(std::make_unique<Impl>(std::move(root), primary)) {}
NativeProfiles::~NativeProfiles() = default;
std::shared_ptr<AdblockProfileState> NativeProfiles::Blocking(BoazHostProfile handle) const { return impl_->Blocking(handle); }
NativeDownloads* NativeProfiles::Downloads(BoazHostProfile handle) const { return impl_->Downloads(handle); }
void NativeProfiles::SetDownloadObserver(DownloadObserver observer) {
  impl_->SetDownloadObserver(std::move(observer));
}
void NativeProfiles::Acquire(std::string identifier, bool private_session,
    base::OnceCallback<void(BoazHostResult, BoazHostProfile)> callback) {
  impl_->Acquire(std::move(identifier), private_session, std::move(callback));
}
Profile* NativeProfiles::Resolve(BoazHostProfile handle) const { return impl_->Resolve(handle); }
bool NativeProfiles::Owns(Profile* profile) const { return impl_->Owns(profile); }
BoazHostProfile NativeProfiles::HandleFor(Profile* profile) const { return impl_->HandleFor(profile); }
BoazHostResult NativeProfiles::ClearCache(BoazHostProfile handle, NativeCacheClearer::Completion completion) {
  return impl_->ClearCache(handle, std::move(completion));
}
BoazHostResult NativeProfiles::Release(BoazHostProfile handle) { return impl_->Release(handle); }
}
