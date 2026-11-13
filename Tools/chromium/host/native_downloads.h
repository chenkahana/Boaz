#ifndef BOAZ_CHROMIUM_NATIVE_DOWNLOADS_H_
#define BOAZ_CHROMIUM_NATIVE_DOWNLOADS_H_
#include <map>
#include <string>
#include <vector>
#include "boaz_host.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_manager.h"
class Profile;
namespace boaz {
class NativeDownloads final : public content::DownloadManager::Observer,
                              public download::DownloadItem::Observer {
 public:
  enum class State { kInProgress, kComplete, kCancelled, kInterrupted };
  enum class Action { kPause, kResume, kCancel };
  struct Snapshot {
    uint64_t id;
    std::string filename;
    int64_t received;
    int64_t total;
    State state;
    bool paused;
    bool can_resume;
    int interrupt_reason;
    int danger_type;
    bool dangerous;
    bool removed = false;
  };
  using Observer = base::RepeatingCallback<void(Snapshot)>;
  explicit NativeDownloads(Profile* profile);
  ~NativeDownloads() override;
  void SetObserver(Observer observer);
  std::vector<Snapshot> Snapshots() const;
  BoazHostResult Perform(uint64_t id, Action action);
 private:
  struct Entry { uint64_t id; raw_ptr<download::DownloadItem> item; };
  void Track(download::DownloadItem* item);
  Snapshot Capture(const Entry& entry) const;
  void Queue(Snapshot snapshot);
  void Deliver();
  void Detach();
  void OnDownloadCreated(content::DownloadManager*, download::DownloadItem*) override;
  void OnDownloadUpdated(download::DownloadItem*) override;
  void OnDownloadDestroyed(download::DownloadItem*) override;
  void ManagerGoingDown(content::DownloadManager*) override;
  raw_ptr<content::DownloadManager> manager_ = nullptr;
  std::map<std::string, Entry> entries_;
  std::map<uint64_t, Snapshot> pending_;
  bool delivery_pending_ = false;
  Observer observer_;
  base::WeakPtrFactory<NativeDownloads> weak_{this};
};
}
#endif
