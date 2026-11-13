#ifndef BOAZ_ADBLOCK_ENGINE_H_
#define BOAZ_ADBLOCK_ENGINE_H_
#include <memory>
#include <string>
#include <string_view>
#include "adblock_url_loader_factory.h"
#include "base/types/expected.h"
#include "boaz_adblock.h"
namespace boaz {
class AdblockEngine {
 public:
  static base::expected<std::shared_ptr<const AdblockEngine>, std::string> Create(
      std::string_view rules, std::string_view resources);
  ~AdblockEngine();
  AdblockEngine(const AdblockEngine&) = delete;
  AdblockEngine& operator=(const AdblockEngine&) = delete;
  AdblockDecision Match(const GURL& url, const GURL& source,
                        std::string_view kind, std::string_view method) const;
  base::expected<std::string, int> Cosmetics(const GURL& url) const;
  base::expected<std::string, int> Selectors(std::string_view input) const;
 private:
  explicit AdblockEngine(BoazAdblockSnapshot* snapshot);
  BoazAdblockSnapshot* const snapshot_;
};
}
#endif
