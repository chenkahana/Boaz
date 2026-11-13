#include "adblock_engine.h"
#include <array>
#include <utility>
#include <fcntl.h>
#include <sys/stat.h>
#include "base/containers/span.h"
#include "base/files/file.h"
#include "base/files/file_util.h"
#include "base/files/scoped_file.h"
#include "base/posix/eintr_wrapper.h"
#include "base/strings/string_number_conversions.h"
#include "base/threading/thread_restrictions.h"
#include "content/public/browser/browser_thread.h"
#include "crypto/hash.h"
#include "base/json/json_reader.h"
#include "base/values.h"
namespace boaz {
namespace {
base::expected<std::string, std::string> ReadAsset(
    int directory, const char* name, size_t size, std::string_view sha256) {
  base::ScopedFD descriptor(HANDLE_EINTR(openat(
      directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)));
  if (!descriptor.is_valid()) return base::unexpected("Blocking asset cannot be opened");
  struct stat info;
  if (fstat(descriptor.get(), &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_size < 0 || static_cast<uint64_t>(info.st_size) != size)
    return base::unexpected("Blocking asset type or size mismatch");
  base::File file(descriptor.release());
  std::string bytes(size, '\0');
  if (!file.ReadAtCurrentPosAndCheck(base::as_writable_byte_span(bytes)))
    return base::unexpected("Blocking asset read failed");
  std::array<uint8_t, 1> extra;
  const auto remaining = file.ReadAtCurrentPos(extra);
  if (!remaining || *remaining != 0)
    return base::unexpected("Blocking asset changed size");
  if (base::HexEncodeLower(crypto::hash::Sha256(bytes)) != sha256)
    return base::unexpected("Blocking asset checksum mismatch");
  return base::ok(std::move(bytes));
}
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
AdblockEngine::AdblockEngine(BoazAdblockSnapshot* snapshot) : snapshot_(snapshot, &boaz_adblock_destroy) {}
AdblockEngine::~AdblockEngine() = default;
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
base::expected<std::shared_ptr<const AdblockEngine>, std::string>
AdblockEngine::LoadPackaged(const base::FilePath& directory) {
  if (content::BrowserThread::CurrentlyOn(content::BrowserThread::UI))
    return base::unexpected("Blocking assets require a worker sequence");
  base::AssertBlockingAllowed();
  if (!directory.IsAbsolute() || directory.ReferencesParent() ||
      base::MakeAbsoluteFilePath(directory) != directory)
    return base::unexpected("Blocking asset directory is not canonical");
  base::ScopedFD folder(HANDLE_EINTR(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)));
  if (!folder.is_valid()) return base::unexpected("Blocking asset directory unavailable");
  for (const auto& component : directory.GetComponents()) {
    if (component == "/") continue;
    if (component.empty() || component == "." || component == "..")
      return base::unexpected("Invalid blocking asset directory component");
    base::ScopedFD next(HANDLE_EINTR(openat(folder.get(), component.c_str(),
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)));
    if (!next.is_valid()) return base::unexpected("Blocking asset directory unavailable");
    folder = std::move(next);
  }
  // Exact runtime inputs from Tools/chromium/adblock/assets.lock.json.
  auto rules = ReadAsset(folder.get(), "rules.txt", 3578300,
      "5aa6b88e1b68464069ec60d52359174f581ea5ce53ff510bd18fcdba931793d7");
  if (!rules.has_value()) return base::unexpected(rules.error());
  auto resources = ReadAsset(folder.get(), "resources.json", 131448,
      "ec29aa0f2260b8b30e59390efab0ddf59402c941c6c6be9f7fe6d88ea1b49468");
  if (!resources.has_value()) return base::unexpected(resources.error());
  auto engine = Create(*rules, *resources);
  if (!engine.has_value()) return base::unexpected("Packaged blocking rules rejected");
  return engine;
}
AdblockDecision AdblockEngine::Match(const GURL& url, const GURL& source,
                                     std::string_view kind, std::string_view method) const {
  using Action = AdblockDecision::Action;
  Buffer output;
  if (boaz_adblock_network(snapshot_.get(), Bytes(url.spec()), Bytes(source.spec()),
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
  const int result = boaz_adblock_cosmetics(snapshot_.get(), Bytes(url.spec()), &output.value);
  if (result != BOAZ_ADBLOCK_OK) return base::unexpected(result);
  return output.Text();
}
base::expected<std::string, int> AdblockEngine::Selectors(std::string_view input) const {
  Buffer output;
  const int result = boaz_adblock_selectors(snapshot_.get(), Bytes(input), &output.value);
  if (result != BOAZ_ADBLOCK_OK) return base::unexpected(result);
  return output.Text();
}
}
