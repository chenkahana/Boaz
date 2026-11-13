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
    for (auto& [id, entry] : entries_)
      if (entry.is_private) ProfileDestroyer::DestroyOTRProfileWhenAppropriate(entry.profile);
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
    entries_.emplace(id, Entry{profile, std::move(keep_alive), std::move(identifier), private_session});
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
        Post(std::move(callback), BOAZ_HOST_OK, id); return;
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
    return found == entries_.end() ? nullptr : found->second.profile.get();
  }
  bool Owns(Profile* profile) const {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!profile) return false;
    for (const auto& [handle, entry] : entries_)
      if (entry.profile == profile) return true;
    return false;
  }
  BoazHostResult Release(BoazHostProfile handle) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto found = entries_.find(handle);
    if (found == entries_.end()) return BOAZ_HOST_INVALID_HANDLE;
    auto entry = std::move(found->second);
    entries_.erase(found);
    if (entry.is_private) ProfileDestroyer::DestroyOTRProfileWhenAppropriate(entry.profile);
    return BOAZ_HOST_OK;
  }
 private:
  const base::FilePath root_;
  raw_ptr<Profile> primary_;
  std::map<BoazHostProfile, Entry> entries_;
  std::map<std::string, std::vector<Completion>> pending_;
  base::WeakPtrFactory<Impl> weak_{this};
};
NativeProfiles::NativeProfiles(base::FilePath root, Profile* primary)
    : impl_(std::make_unique<Impl>(std::move(root), primary)) {}
NativeProfiles::~NativeProfiles() = default;
void NativeProfiles::Acquire(std::string identifier, bool private_session,
    base::OnceCallback<void(BoazHostResult, BoazHostProfile)> callback) {
  impl_->Acquire(std::move(identifier), private_session, std::move(callback));
}
Profile* NativeProfiles::Resolve(BoazHostProfile handle) const { return impl_->Resolve(handle); }
bool NativeProfiles::Owns(Profile* profile) const { return impl_->Owns(profile); }
BoazHostResult NativeProfiles::Release(BoazHostProfile handle) { return impl_->Release(handle); }
}
