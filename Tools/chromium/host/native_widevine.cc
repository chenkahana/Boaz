#include "native_widevine.h"

#include "base/logging.h"
#include "base/version.h"
#include "boaz/buildflags.h"
#include "content/public/browser/browser_thread.h"

#if BUILDFLAG(BOAZ_WIDEVINE_ENABLED)
#include <Security/Security.h>

#include "base/apple/foundation_util.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/native_library.h"
#include "base/no_destructor.h"
#include "base/path_service.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/browser_process.h"
#include "chrome/common/chrome_paths.h"
#include "components/component_updater/component_updater_service.h"
#include "media/cdm/cdm_paths.h"
#include "third_party/widevine/cdm/widevine_cdm_common.h"
#endif

namespace boaz {
#if BUILDFLAG(BOAZ_WIDEVINE_ENABLED)
namespace {
// Chromium's Widevine component (chrome/browser/component_updater/widevine_cdm_component_installer.cc).
constexpr char kWidevineComponentID[] = "oimompecagnajdejgnnjijobebaeigek";

// The installed version whose signature was last checked, and the verdict.
struct Verification {
  std::string version;
  bool checked = false, valid = false;
};
Verification& Current() {
  static base::NoDestructor<Verification> verification;
  return *verification;
}

// Blocking. A truncated, altered or re-signed CDM fails here instead of failing later in the CDM process.
bool SignedByGoogle(const std::string& version) {
  base::FilePath base;
  if (!base::PathService::Get(chrome::DIR_COMPONENT_UPDATED_WIDEVINE_CDM, &base)) return false;
  const base::FilePath library = media::GetPlatformSpecificDirectory(base.AppendASCII(version))
      .AppendASCII(base::GetNativeLibraryName(kWidevineCdmLibraryName));
  base::apple::ScopedCFTypeRef<SecStaticCodeRef> code;
  base::apple::ScopedCFTypeRef<SecRequirementRef> requirement;
  const OSStatus status = SecStaticCodeCreateWithPath(base::apple::FilePathToCFURL(library).get(),
      kSecCSDefaultFlags, code.InitializeInto());
  if (status != errSecSuccess ||
      SecRequirementCreateWithString(
          CFSTR("anchor apple generic and certificate leaf[subject.OU] = \"EQHXZ8M8AV\""),
          kSecCSDefaultFlags, requirement.InitializeInto()) != errSecSuccess) {
    LOG(ERROR) << "Boaz Widevine: cannot read the CDM signature (" << status << ")";
    return false;
  }
  const OSStatus validity = SecStaticCodeCheckValidity(code.get(), kSecCSStrictValidate, requirement.get());
  if (validity != errSecSuccess) LOG(ERROR) << "Boaz Widevine: CDM " << version << " failed signature check (" << validity << ")";
  return validity == errSecSuccess;
}

std::string InstalledVersion() {
  auto* updater = g_browser_process ? g_browser_process->component_updater() : nullptr;
  if (!updater) return {};
  for (const auto& component : updater->GetComponents()) {
    if (component.id == kWidevineComponentID && component.version.IsValid() &&
        component.version != base::Version("0.0.0.0")) {
      return component.version.GetString();
    }
  }
  return {};
}
}  // namespace
#endif

BoazHostWidevineState NativeWidevineState(std::string* version) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  version->clear();
#if BUILDFLAG(BOAZ_WIDEVINE_ENABLED)
  const std::string installed = InstalledVersion();
  if (installed.empty()) return BOAZ_WIDEVINE_NOT_INSTALLED;
  auto& verification = Current();
  if (verification.version != installed) {
    verification = {installed};
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&SignedByGoogle, installed),
        base::BindOnce([](std::string checked, bool valid) {
          auto& current = Current();
          if (current.version != checked) return;
          current.checked = true;
          current.valid = valid;
          VLOG(1) << "Boaz Widevine: CDM " << checked << (valid ? " verified" : " rejected");
        }, installed));
  }
  // Until the check passes, Widevine requests keep the not-installed route.
  if (!verification.checked || !verification.valid) return BOAZ_WIDEVINE_NOT_INSTALLED;
  *version = installed;
  return BOAZ_WIDEVINE_READY;
#else
  return BOAZ_WIDEVINE_DISABLED;
#endif
}
}  // namespace boaz
