#include "adblock_profile_state.h"
#include "content/public/browser/browser_thread.h"
namespace boaz {
AdblockProfileState::AdblockProfileState()
    : config_(std::make_shared<const Config>()) {}
AdblockProfileState::~AdblockProfileState() = default;
bool AdblockProfileState::Publish(Config config) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  const auto current = std::atomic_load(&config_);
  if (current->closed || config.closed || (config.enabled && !config.engine) ||
      config.exception_sites.size() > 10000) return false;
  for (const auto& value : config.exception_sites) {
    if (value.empty() || value.size() > 2048) return false;
    const GURL url(value);
    if (!url.is_valid() || !url.SchemeIsHTTPOrHTTPS()) return false;
    const net::SchemefulSite site(url);
    // Canonical serialization excludes paths, ports, credentials, fragments,
    // and subdomains below the registrable domain. Never broaden silently.
    if (site.opaque() || site.Serialize() != value) return false;
  }
  std::atomic_store(&config_, std::make_shared<const Config>(std::move(config)));
  return true;
}
void AdblockProfileState::Close() {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Config closed;
  closed.closed = true;
  std::atomic_store(&config_, std::make_shared<const Config>(std::move(closed)));
}
AdblockDecision AdblockProfileState::Evaluate(
    const GURL& url, const GURL& source, std::string_view kind,
    std::string_view method, const std::optional<net::SchemefulSite>& top_level_site) const {
  const auto config = std::atomic_load(&config_);
  if (config->closed) return {AdblockDecision::Action::kUnsupported, {}, {}};
  if (!config->enabled) return {AdblockDecision::Action::kAllow, {}, {}};
  if (!config->engine || !top_level_site || top_level_site->opaque() ||
      !top_level_site->GetURL().SchemeIsHTTPOrHTTPS() ||
      !source.is_valid() || !source.SchemeIsHTTPOrHTTPS())
    return {AdblockDecision::Action::kUnsupported, {}, {}};
  if (config->exception_sites.contains(top_level_site->Serialize()))
    return {AdblockDecision::Action::kAllow, {}, {}};
  return config->engine->Match(url, source, kind, method);
}
}
