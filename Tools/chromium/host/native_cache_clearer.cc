#include "boaz/native_cache_clearer.h"

#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_thread.h"

namespace boaz {
NativeCacheClearer::NativeCacheClearer(content::BrowserContext* context)
    : context_(context) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(context_);
}

NativeCacheClearer::~NativeCacheClearer() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(!busy());
  CHECK(!remover_);
}

bool NativeCacheClearer::busy() const {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  return !completion_.is_null();
}

bool NativeCacheClearer::Clear(Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (busy() || !completion) return false;
  auto* remover = context_->GetBrowsingDataRemover();
  if (!remover) return false;
  completion_ = std::move(completion);
  remover_ = remover;
  remover->AddObserver(this);
  remover->RemoveAndReply(base::Time(), base::Time::Max(),
      content::BrowsingDataRemover::DATA_TYPE_CACHE,
      content::BrowsingDataRemover::ORIGIN_TYPE_UNPROTECTED_WEB, this);
  return true;
}

void NativeCacheClearer::OnBrowsingDataRemoverDone(uint64_t failed_data_types) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(busy());
  CHECK(remover_);
  remover_->RemoveObserver(this);
  remover_ = nullptr;
  auto completion = std::move(completion_);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(std::move(completion),
          failed_data_types == 0 ? Result::kSuccess : Result::kFailed));
}
}  // namespace boaz
