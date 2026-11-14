#include "boaz/native_cookie_import.h"

#include <array>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>
#include "base/barrier_callback.h"
#include "base/check.h"
#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/storage_partition.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "net/cookies/canonical_cookie.h"
#include "net/cookies/cookie_access_result.h"
#include "net/cookies/cookie_options.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
#include "url/gurl.h"

namespace boaz {
namespace {
struct Candidate {
  std::unique_ptr<net::CanonicalCookie> cookie;
  GURL source;
};

std::optional<Candidate> Sanitize(const BoazHostCookie& input, base::Time now) {
  if (!input.name || !input.value || !input.domain || !input.path ||
      input.same_site < 0 || input.same_site > 3 || input.secure > 1 || input.http_only > 1)
    return std::nullopt;
  std::string domain = input.domain, path = input.path;
  if (path.empty()) path = "/";
  std::string host = domain.starts_with('.') ? domain.substr(1) : domain;
  if (host.empty()) return std::nullopt;
  base::Time expiry;
  if (input.expires_unix != 0) {
    expiry = base::Time::FromSecondsSinceUnixEpoch(input.expires_unix);
    if (expiry <= now) return std::nullopt;
  }
  GURL source((input.secure ? "https://" : "http://") + host + path);
  if (!source.is_valid()) return std::nullopt;
  constexpr std::array kSameSite = {net::CookieSameSite::UNSPECIFIED,
      net::CookieSameSite::NO_RESTRICTION, net::CookieSameSite::LAX_MODE,
      net::CookieSameSite::STRICT_MODE};
  net::CookieInclusionStatus status;
  auto cookie = net::CanonicalCookie::CreateSanitizedCookie(source, input.name, input.value,
      domain.starts_with('.') ? domain : std::string(), path, now, expiry, now,
      input.secure, input.http_only, kSameSite[static_cast<size_t>(input.same_site)], net::COOKIE_PRIORITY_DEFAULT,
      std::nullopt, &status);
  if (!cookie) return std::nullopt;
  return Candidate{std::move(cookie), std::move(source)};
}
}  // namespace

void ImportNativeCookies(content::BrowserContext* context, const BoazHostCookie* cookies,
                         size_t count, CookieImportCompletion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(context);
  CHECK(completion);
  const base::Time now = base::Time::Now();
  std::vector<Candidate> candidates;
  candidates.reserve(count);
  // SAFETY: the C ABI caller supplies `count` readable records at `cookies`.
  for (const auto& input : UNSAFE_BUFFERS(base::span(cookies, count)))
    if (auto candidate = Sanitize(input, now)) candidates.push_back(std::move(*candidate));
  const uint32_t rejected = static_cast<uint32_t>(count - candidates.size());
  auto done = base::BarrierCallback<bool>(candidates.size(), base::BindOnce(
      [](CookieImportCompletion completion, uint32_t rejected, std::vector<bool> results) {
        uint32_t imported = 0;
        for (bool result : results) imported += result;
        rejected += static_cast<uint32_t>(results.size()) - imported;
        base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
            base::BindOnce(std::move(completion), imported, rejected));
      }, std::move(completion), rejected));
  if (candidates.empty()) return;
  auto* manager = context->GetDefaultStoragePartition()->GetCookieManagerForBrowserProcess();
  net::CookieOptions options;
  options.set_include_httponly();
  options.set_same_site_cookie_context(net::CookieOptions::SameSiteCookieContext::MakeInclusive());
  for (auto& candidate : candidates) {
    manager->SetCanonicalCookie(*candidate.cookie, candidate.source, options, base::BindOnce(
        [](base::OnceCallback<void(bool)> done, net::CookieAccessResult result) {
          std::move(done).Run(result.status.IsInclude());
        }, mojo::WrapCallbackWithDefaultInvokeIfNotRun(base::OnceCallback<void(bool)>(done), false)));
  }
}
}  // namespace boaz
