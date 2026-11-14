#ifndef BOAZ_CHROMIUM_NATIVE_CACHE_CLEARER_H_
#define BOAZ_CHROMIUM_NATIVE_CACHE_CLEARER_H_

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "content/public/browser/browsing_data_remover.h"

namespace content { class BrowserContext; }

namespace boaz {
// UI-thread only. Owner keeps BrowserContext alive and drains Clear before destruction.
class NativeCacheClearer final : public content::BrowsingDataRemover::Observer {
 public:
  enum class Result { kSuccess, kFailed };
  using Completion = base::OnceCallback<void(Result)>;
  explicit NativeCacheClearer(content::BrowserContext* context);
  ~NativeCacheClearer() override;
  bool busy() const;
  // False rejects without a callback; true posts exactly one completion.
  bool Clear(Completion completion);

 private:
  void OnBrowsingDataRemoverDone(uint64_t failed_data_types) override;
  const raw_ptr<content::BrowserContext> context_;
  raw_ptr<content::BrowsingDataRemover> remover_ = nullptr;
  Completion completion_;
};
}  // namespace boaz
#endif
