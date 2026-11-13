#ifndef BOAZ_CHROMIUM_NATIVE_AUTOMATION_H_
#define BOAZ_CHROMIUM_NATIVE_AUTOMATION_H_
#include <cstdint>
#include <memory>
#include <string>
#include "base/files/file_path.h"
class PrefService;
namespace boaz {
class NativeAutomation {
 public:
  enum class State { kDisabled, kStarting, kReady, kFailed };
  struct Snapshot {
    State state = State::kDisabled;
    uint16_t port = 0;
    std::string error;
  };
  NativeAutomation(base::FilePath canonical_product_root, PrefService* local_state);
  ~NativeAutomation();
  void Start(bool enabled, bool policy_allowed);
  void Stop();
  Snapshot Status() const;
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
#endif
