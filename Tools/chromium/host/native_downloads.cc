#include "native_downloads.h"
#include <limits>
#include <utility>
#include "base/check.h"
#include "base/notreached.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_thread.h"
namespace boaz {
NativeDownloads::NativeDownloads(Profile* profile) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(profile);
  manager_ = profile->GetDownloadManager();
  CHECK(manager_);
  manager_->AddObserver(this);
  download::SimpleDownloadManager::DownloadVector items;
  manager_->GetAllDownloads(&items);
  for (const auto& item : items) Track(item.get());
}
NativeDownloads::~NativeDownloads() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  weak_.InvalidateWeakPtrs();
  Detach();
}
void NativeDownloads::SetObserver(Observer observer) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  observer_ = std::move(observer);
  for (const auto& [guid, entry] : entries_) Queue(Capture(entry));
}
void NativeDownloads::Track(download::DownloadItem* item) {
  if (!item || entries_.contains(item->GetGuid())) return;
  static uint64_t next = 1;
  CHECK_LT(next, std::numeric_limits<uint64_t>::max());
  auto it = entries_.emplace(item->GetGuid(), Entry{next++, item}).first;
  item->AddObserver(this);
  Queue(Capture(it->second));
}
NativeDownloads::Snapshot NativeDownloads::Capture(const Entry& entry) const {
  const auto* item = entry.item.get();
  State state;
  switch (item->GetState()) {
    case download::DownloadItem::IN_PROGRESS: state = State::kInProgress; break;
    case download::DownloadItem::COMPLETE: state = State::kComplete; break;
    case download::DownloadItem::CANCELLED: state = State::kCancelled; break;
    case download::DownloadItem::INTERRUPTED: state = State::kInterrupted; break;
    case download::DownloadItem::MAX_DOWNLOAD_STATE: NOTREACHED();
  }
  return {entry.id, item->GetFileNameToReportUser().BaseName().AsUTF8Unsafe(),
          item->GetReceivedBytes(), item->GetTotalBytes(), state, item->IsPaused(),
          item->CanResume(), static_cast<int>(item->GetLastReason()),
          static_cast<int>(item->GetDangerType()), item->IsDangerous()};
}
std::vector<NativeDownloads::Snapshot> NativeDownloads::Snapshots() const {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  std::vector<Snapshot> result;
  for (const auto& [guid, entry] : entries_) result.push_back(Capture(entry));
  return result;
}
void NativeDownloads::Queue(Snapshot snapshot) {
  pending_.insert_or_assign(snapshot.id, std::move(snapshot));
  if (delivery_pending_) return;
  delivery_pending_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&NativeDownloads::Deliver, weak_.GetWeakPtr()));
}
void NativeDownloads::Deliver() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  delivery_pending_ = false;
  auto events = std::exchange(pending_, {});
  auto observer = observer_;
  auto alive = weak_.GetWeakPtr();
  if (!observer) return;
  for (auto& [id, snapshot] : events) {
    observer.Run(std::move(snapshot));
    if (!alive) return;
  }
}
BoazHostResult NativeDownloads::Perform(uint64_t id, Action action) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!manager_ || !id) return BOAZ_HOST_INVALID_HANDLE;
  download::DownloadItem* item = nullptr;
  for (const auto& [guid, entry] : entries_) {
    if (entry.id == id) {
      item = manager_->GetDownloadByGuid(guid);
      if (item != entry.item) return BOAZ_HOST_INVALID_HANDLE;
      break;
    }
  }
  if (!item) return BOAZ_HOST_INVALID_HANDLE;
  const auto state = item->GetState();
  switch (action) {
    case Action::kPause:
      if (state != download::DownloadItem::IN_PROGRESS || item->IsPaused()) return BOAZ_HOST_UNAVAILABLE;
      item->Pause();
      return BOAZ_HOST_OK;
    case Action::kResume:
      if (item->IsDangerous() || !item->CanResume() ||
          (state != download::DownloadItem::INTERRUPTED && !item->IsPaused())) return BOAZ_HOST_UNAVAILABLE;
      item->Resume(true);
      return BOAZ_HOST_OK;
    case Action::kCancel:
      if (state != download::DownloadItem::IN_PROGRESS && state != download::DownloadItem::INTERRUPTED)
        return BOAZ_HOST_UNAVAILABLE;
      item->Cancel(true);
      return BOAZ_HOST_OK;
  }
  return BOAZ_HOST_INVALID_ARGUMENT;
}
void NativeDownloads::OnDownloadCreated(content::DownloadManager* manager, download::DownloadItem* item) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (manager == manager_) Track(item);
}
void NativeDownloads::OnDownloadUpdated(download::DownloadItem* item) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto it = entries_.find(item->GetGuid());
  if (it != entries_.end() && it->second.item == item) Queue(Capture(it->second));
}
void NativeDownloads::OnDownloadDestroyed(download::DownloadItem* item) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto it = entries_.find(item->GetGuid());
  if (it == entries_.end() || it->second.item != item) return;
  auto snapshot = Capture(it->second);
  snapshot.removed = true;
  item->RemoveObserver(this);
  entries_.erase(it);
  Queue(std::move(snapshot));
}
void NativeDownloads::Detach() {
  for (auto& [guid, entry] : entries_) entry.item->RemoveObserver(this);
  entries_.clear();
  if (manager_) manager_->RemoveObserver(this);
  manager_ = nullptr;
}
void NativeDownloads::ManagerGoingDown(content::DownloadManager* manager) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (manager != manager_) return;
  for (const auto& [guid, entry] : entries_) {
    auto snapshot = Capture(entry);
    snapshot.removed = true;
    Queue(std::move(snapshot));
  }
  Detach();
}
}
