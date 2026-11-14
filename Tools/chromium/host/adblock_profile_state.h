#ifndef BOAZ_ADBLOCK_PROFILE_STATE_H_
#define BOAZ_ADBLOCK_PROFILE_STATE_H_
#include <atomic>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include "adblock_engine.h"
#include "net/base/schemeful_site.h"
namespace boaz {
class AdblockProfileState final {
 public:
  struct Config {
    bool enabled = true;
    bool closed = false;
    std::set<std::string, std::less<>> exception_sites;
    std::shared_ptr<const AdblockEngine> engine;
  };
  AdblockProfileState();
  ~AdblockProfileState();
  // UI-thread publication. Invalid configurations leave the old snapshot intact.
  bool Publish(Config);
  void Close();
  AdblockDecision Evaluate(const GURL& url, const GURL& source,
      std::string_view kind, std::string_view method,
      const std::optional<net::SchemefulSite>& top_level_site) const;
 private:
  std::shared_ptr<const Config> config_;
};
}
#endif
