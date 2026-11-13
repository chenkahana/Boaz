#include "adblock_profile_state.h"
#include "content/public/browser/browser_thread.h"
namespace boaz {
AdblockProfileState::AdblockProfileState()
    : config_(std::make_shared<const Config>()) {}
AdblockProfileState::~AdblockProfileState() = default;
bool AdblockProfileState::Publish(Config config) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  const auto current = config_.load();
  if (current->closed || config.closed || (config.enabled && !config.engine) ||
      config.exception_hosts.size() > 10000) return false;
  for (const auto& host : config.exception_hosts) {
    if (host.empty() || host.size() > 253 || host.find('*') != std::string::npos) return false;
    GURL url("https://" + host + "/");
    if (!url.is_valid() || url.host() != host || url.has_port() ||
        url.has_username() || url.has_password() || url.path() != "/" ||
        url.has_query() || url.has_ref()) return false;
  }
  config_.store(std::make_shared<const Config>(std::move(config)));
  return true;
}
void AdblockProfileState::Close() {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Config closed;
  closed.closed = true;
  config_.store(std::make_shared<const Config>(std::move(closed)));
}
AdblockDecision AdblockProfileState::Evaluate(
    const GURL& url, const GURL& source, std::string_view kind,
    std::string_view method, const std::optional<url::Origin>& top_level_origin) const {
  const auto config = config_.load();
  if (config->closed) return {AdblockDecision::Action::kUnsupported, {}, {}};
  if (!config->enabled) return {AdblockDecision::Action::kAllow, {}, {}};
  if (!config->engine || !top_level_origin || top_level_origin->opaque() ||
      !top_level_origin->GetURL().SchemeIsHTTPOrHTTPS() ||
      !source.is_valid() || !source.SchemeIsHTTPOrHTTPS())
    return {AdblockDecision::Action::kUnsupported, {}, {}};
  if (config->exception_hosts.contains(top_level_origin->GetURL().host()))
    return {AdblockDecision::Action::kAllow, {}, {}};
  return config->engine->Match(url, source, kind, method);
}
}
