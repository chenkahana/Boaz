#include "adblock_engine.h"
#include "base/json/json_reader.h"
#include "base/values.h"
namespace boaz {
namespace {
BoazAdblockBytes Bytes(std::string_view value) {
  return {reinterpret_cast<const uint8_t*>(value.data()), value.size()};
}
class Buffer {
 public:
  ~Buffer() { boaz_adblock_buffer_free(value); }
  std::string Text() const {
    return value.len ? std::string(reinterpret_cast<const char*>(value.data), value.len)
                     : std::string();
  }
  BoazAdblockBuffer value{};
};
}
AdblockEngine::AdblockEngine(BoazAdblockSnapshot* snapshot) : snapshot_(snapshot) {}
AdblockEngine::~AdblockEngine() { boaz_adblock_destroy(snapshot_); }
base::expected<std::shared_ptr<const AdblockEngine>, std::string>
AdblockEngine::Create(std::string_view rules, std::string_view resources) {
  BoazAdblockSnapshot* snapshot = nullptr;
  Buffer diagnostics;
  const int result = boaz_adblock_create(Bytes(rules), Bytes(resources), &snapshot,
                                          &diagnostics.value);
  if (result != BOAZ_ADBLOCK_OK || !snapshot) {
    if (snapshot) boaz_adblock_destroy(snapshot);
    return base::unexpected("Content-blocking rules rejected (" + std::to_string(result) +
                            "): " + diagnostics.Text());
  }
  return std::shared_ptr<const AdblockEngine>(new AdblockEngine(snapshot));
}
AdblockDecision AdblockEngine::Match(const GURL& url, const GURL& source,
                                     std::string_view kind, std::string_view method) const {
  using Action = AdblockDecision::Action;
  Buffer output;
  if (boaz_adblock_network(snapshot_, Bytes(url.spec()), Bytes(source.spec()),
                           Bytes(kind), Bytes(method), &output.value) != BOAZ_ADBLOCK_OK)
    return {Action::kUnsupported};
  auto parsed = base::JSONReader::ReadDict(output.Text(), base::JSON_PARSE_RFC);
  if (!parsed) return {Action::kUnsupported};
  const auto blocked = parsed->FindBool("should_block");
  const auto* result = parsed->FindDict("result");
  if (!blocked || !result) return {Action::kUnsupported};
  if (*blocked) {
    if (const auto* redirect = result->FindString("redirect"))
      return {Action::kResourceReplacement, std::nullopt, *redirect};
    return {Action::kBlock};
  }
  if (const auto* rewrite = result->FindString("rewritten_url"))
    return {Action::kRewrite, GURL(*rewrite)};
  return {Action::kAllow};
}
base::expected<std::string, int> AdblockEngine::Cosmetics(const GURL& url) const {
  Buffer output;
  const int result = boaz_adblock_cosmetics(snapshot_, Bytes(url.spec()), &output.value);
  if (result != BOAZ_ADBLOCK_OK) return base::unexpected(result);
  return output.Text();
}
base::expected<std::string, int> AdblockEngine::Selectors(std::string_view input) const {
  Buffer output;
  const int result = boaz_adblock_selectors(snapshot_, Bytes(input), &output.value);
  if (result != BOAZ_ADBLOCK_OK) return base::unexpected(result);
  return output.Text();
}
}
