#include "native_automation.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <cstdlib>
#include <string_view>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "base/location.h"
#include "base/containers/span.h"
#include "base/files/scoped_file.h"
#include "base/json/json_writer.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/devtools_socket_factory.h"
#include "crypto/random.h"
#include "net/base/net_errors.h"
#include "net/log/net_log_source.h"
#include "net/socket/tcp_server_socket.h"

namespace boaz {
namespace {
void RequireUI() { CHECK_CURRENTLY_ON(content::BrowserThread::UI); }
class LoopbackFactory final : public content::DevToolsSocketFactory {
 public:
  std::unique_ptr<net::ServerSocket> CreateForHttpServer() override {
    auto socket = std::make_unique<net::TCPServerSocket>(nullptr, net::NetLogSource());
    if (socket->ListenWithAddressAndPort("127.0.0.1", 0, 10) != net::OK)
      return nullptr;
    return socket;
  }
  std::unique_ptr<net::ServerSocket> CreateForTethering(std::string*) override {
    return nullptr;
  }
};
bool Canonical(const base::FilePath& path) {
  char* resolved = realpath(path.value().c_str(), nullptr);
  if (!resolved) return false;
  bool same = path.value() == resolved;
  free(resolved);
  return same;
}
std::string RandomHex() {
  return base::ToLowerASCII(base::HexEncode(crypto::RandBytesAsArray<32>()));
}
}

class NativeAutomation::Impl {
 public:
  Impl(base::FilePath root, PrefService* local_state)
      : root_(std::move(root)), local_state_(local_state) {
    RequireUI();
    CHECK(local_state_);
    policy_registrar_.Init(local_state_);
    policy_registrar_.Add(prefs::kDevToolsRemoteDebuggingAllowed,
        base::BindRepeating(&Impl::PolicyChanged, base::Unretained(this)));
  }
  ~Impl() {
    RequireUI();
    policy_registrar_.RemoveAll();
    Stop();
  }
  void Start(bool enabled, bool allowed) {
    RequireUI();
    Stop();
    if (!enabled) return;
    if (!allowed || !local_state_->GetBoolean(prefs::kDevToolsRemoteDebuggingAllowed)) { Fail("Automation is disabled by policy."); return; }
    if (!Canonical(root_)) { Fail("Automation storage is unavailable."); return; }
    base::ScopedFD root_fd(open(root_.value().c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    struct stat root_stat;
    if (!root_fd.is_valid() || fstat(root_fd.get(), &root_stat) ||
        root_stat.st_uid != getuid()) {
      Fail("Automation storage ownership is invalid."); return;
    }
    if (mkdirat(root_fd.get(), "Automation", 0700) && errno != EEXIST) {
      Fail("Cannot create automation storage."); return;
    }
    directory_.reset(openat(root_fd.get(), "Automation", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    struct stat info;
    if (!directory_.is_valid() || fstat(directory_.get(), &info) ||
        info.st_uid != getuid() || (info.st_mode & 07777) != 0700 ||
        !Canonical(root_.AppendASCII("Automation"))) {
      Fail("Automation storage must be a private owned directory."); return;
    }
    if (!content::DevToolsAgentHost::GetRemoteDebuggingServerAddress().empty()) {
      Fail("Another debugging server is already active."); return;
    }
    token_ = RandomHex();
    run_ = RandomHex();
    snapshot_ = {State::kStarting, 0, {}};
    deadline_ = base::TimeTicks::Now() + base::Seconds(10);
    owns_server_ = true;
    content::DevToolsAgentHost::StartRemoteDebuggingServer(
        std::make_unique<LoopbackFactory>(), base::FilePath(), base::FilePath(),
        content::DevToolsAgentHost::RemoteDebuggingServerMode::kDefault, token_);
    timer_.Start(FROM_HERE, base::Milliseconds(100), this, &Impl::Poll);
  }
  void Stop() {
    RequireUI();
    timer_.Stop();
    if (owns_server_) content::DevToolsAgentHost::StopRemoteDebuggingServer();
    owns_server_ = false;
    if (directory_.is_valid() && !filename_.empty()) {
      struct stat info;
      if (!fstatat(directory_.get(), filename_.c_str(), &info, AT_SYMLINK_NOFOLLOW) &&
          info.st_dev == file_device_ && info.st_ino == file_inode_ && S_ISREG(info.st_mode))
        unlinkat(directory_.get(), filename_.c_str(), 0);
    }
    filename_.clear();
    directory_.reset();
    token_.clear();
    run_.clear();
    snapshot_ = {};
  }
  Snapshot Status() const { RequireUI(); return snapshot_; }
 private:
  void PolicyChanged() {
    RequireUI();
    if (!local_state_->GetBoolean(prefs::kDevToolsRemoteDebuggingAllowed))
      Fail("Automation is disabled by policy.");
  }
  void Fail(std::string error) {
    Stop();
    snapshot_ = {State::kFailed, 0, std::move(error)};
  }
  void Poll() {
    RequireUI();
    const std::string address = content::DevToolsAgentHost::GetRemoteDebuggingServerAddress();
    if (address.empty()) {
      if (base::TimeTicks::Now() >= deadline_) Fail("Automation could not start.");
      return;
    }
    unsigned int port = 0;
    constexpr std::string_view prefix = "127.0.0.1:";
    if (!base::StartsWith(address, prefix) ||
        !base::StringToUint(std::string_view(address).substr(prefix.size()), &port) ||
        port == 0 || port > 65535) {
      Fail("Automation did not bind to the required local address."); return;
    }
    if (!Publish(static_cast<uint16_t>(port))) {
      Fail("Cannot publish private automation connection details."); return;
    }
    timer_.Stop();
    snapshot_ = {State::kReady, static_cast<uint16_t>(port), {}};
  }
  bool Publish(uint16_t port) {
    base::DictValue record;
    record.Set("version", 1);
    record.Set("pid", static_cast<int>(getpid()));
    record.Set("run", run_);
    record.Set("port", static_cast<int>(port));
    record.Set("token", token_);
    auto json = base::WriteJson(record);
    if (!json || json->size() > 1024) return false;
    const std::string name = "boaz-" + base::NumberToString(getpid()) + "-" + run_ + ".json";
    base::ScopedFD file(openat(directory_.get(), name.c_str(),
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
    if (!file.is_valid()) return false;
    struct stat info;
    if (fstat(file.get(), &info)) return false;
    filename_ = name;
    file_device_ = info.st_dev;
    file_inode_ = info.st_ino;
    if (!S_ISREG(info.st_mode) || info.st_uid != getuid() ||
        (info.st_mode & 07777) != 0600 || info.st_nlink != 1) return false;
    size_t offset = 0;
    while (offset < json->size()) {
      const auto remaining = base::as_byte_span(*json).subspan(offset);
      ssize_t count = write(file.get(), remaining.data(), remaining.size());
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0) return false;
      offset += static_cast<size_t>(count);
    }
    return fsync(file.get()) == 0 && fsync(directory_.get()) == 0;
  }
  const base::FilePath root_;
  raw_ptr<PrefService> local_state_;
  PrefChangeRegistrar policy_registrar_;
  Snapshot snapshot_;
  base::ScopedFD directory_;
  std::string token_, run_, filename_;
  dev_t file_device_ = 0;
  ino_t file_inode_ = 0;
  bool owns_server_ = false;
  base::TimeTicks deadline_;
  base::RepeatingTimer timer_;
};
NativeAutomation::NativeAutomation(base::FilePath root, PrefService* local_state)
    : impl_(std::make_unique<Impl>(std::move(root), local_state)) {}
NativeAutomation::~NativeAutomation() = default;
void NativeAutomation::Start(bool enabled, bool policy_allowed) { impl_->Start(enabled, policy_allowed); }
void NativeAutomation::Stop() { impl_->Stop(); }
NativeAutomation::Snapshot NativeAutomation::Status() const { return impl_->Status(); }
}
