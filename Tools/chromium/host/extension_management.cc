#include "extension_management.h"
#include <algorithm>
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_prefs.h"
#include "extensions/common/permissions/permission_set.h"
#include "extensions/common/permissions/permissions_data.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest.h"

namespace boaz {
namespace {
bool CanDisable(Profile* profile, const extensions::Extension& extension) {
  if (extensions::Manifest::IsComponentLocation(extension.location())) return false;
  auto* system = extensions::ExtensionSystem::Get(profile);
  auto* policy = system ? system->management_policy() : nullptr;
  return policy && policy->UserMayModifySettings(&extension, nullptr) &&
         !policy->MustRemainEnabled(&extension, nullptr);
}
bool CanEnable(Profile* profile, const extensions::Extension& extension) {
  if (extensions::Manifest::IsComponentLocation(extension.location())) return false;
  auto* prefs = extensions::ExtensionPrefs::Get(profile);
  auto* system = extensions::ExtensionSystem::Get(profile);
  auto* policy = system ? system->management_policy() : nullptr;
  if (!prefs || !policy ||
      !prefs->HasOnlyDisableReason(extension.id(), extensions::disable_reason::DISABLE_USER_ACTION) ||
      prefs->DidExtensionEscalatePermissions(extension.id()) ||
      !policy->UserMayModifySettings(&extension, nullptr) ||
      policy->MustRemainDisabled(&extension, nullptr)) return false;
  auto granted = prefs->GetGrantedPermissions(extension.id());
  return granted && granted->Contains(extension.permissions_data()->active_permissions());
}
bool CanUninstall(Profile* profile, const extensions::Extension& extension) {
  if (extensions::Manifest::IsComponentLocation(extension.location())) return false;
  auto* system = extensions::ExtensionSystem::Get(profile);
  auto* policy = system ? system->management_policy() : nullptr;
  return policy && policy->UserMayModifySettings(&extension, nullptr) &&
         !policy->MustRemainInstalled(&extension, nullptr);
}
bool ValidID(const std::string& id) {
  return id.size() == 32 && std::ranges::all_of(id, [](char c) { return c >= 'a' && c <= 'p'; });
}
}
bool NeedsExtensionPermissionReview(Profile* profile, const std::string& id) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!profile || profile->IsOffTheRecord() || profile->ShutdownStarted() || !ValidID(id)) return false;
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* prefs = extensions::ExtensionPrefs::Get(profile);
  auto* system = extensions::ExtensionSystem::Get(profile);
  auto* policy = system ? system->management_policy() : nullptr;
  const auto* extension = registry ? registry->disabled_extensions().GetByID(id) : nullptr;
  return extension && prefs && policy &&
      !extensions::Manifest::IsComponentLocation(extension->location()) &&
      prefs->HasOnlyDisableReason(id, extensions::disable_reason::DISABLE_PERMISSIONS_INCREASE) &&
      policy->UserMayModifySettings(extension, nullptr) &&
      !policy->MustRemainDisabled(extension, nullptr);
}
std::vector<ManagedExtension> ListManagedExtensions(Profile* profile) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  std::vector<ManagedExtension> result;
  if (!profile || profile->IsOffTheRecord()) return result;
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  if (!registry) return result;
  for (const auto& extension : registry->enabled_extensions()) {
    if (extensions::Manifest::IsComponentLocation(extension->location())) continue;
    result.push_back({extension->id(), extension->name(), extension->version().GetString(),
                      true, CanDisable(profile, *extension), false, CanUninstall(profile, *extension), false});
  }
  for (const auto& extension : registry->disabled_extensions()) {
    if (extensions::Manifest::IsComponentLocation(extension->location())) continue;
    result.push_back({extension->id(), extension->name(), extension->version().GetString(), false, false, CanEnable(profile, *extension), CanUninstall(profile, *extension), NeedsExtensionPermissionReview(profile, extension->id())});
  }
  std::ranges::sort(result, {}, &ManagedExtension::id);
  return result;
}
BoazHostResult UninstallManagedExtension(Profile* profile, const std::string& id) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!profile || profile->IsOffTheRecord() || profile->ShutdownStarted()) return BOAZ_HOST_UNAVAILABLE;
  if (!ValidID(id)) return BOAZ_HOST_INVALID_ARGUMENT;
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* registrar = extensions::ExtensionRegistrar::Get(profile);
  if (!registry || !registrar) return BOAZ_HOST_UNAVAILABLE;
  const auto* extension = registry->GetInstalledExtension(id);
  if (!extension) return BOAZ_HOST_INVALID_ARGUMENT;
  if (!CanUninstall(profile, *extension)) return BOAZ_HOST_UNAVAILABLE;
  // Registry removal is synchronous; disk and site-data cleanup is asynchronous.
  if (!registrar->UninstallExtension(id, extensions::UNINSTALL_REASON_USER_INITIATED,
                                    nullptr)) return BOAZ_HOST_UNAVAILABLE;
  return !registry->GetInstalledExtension(id) ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
}
BoazHostResult EnableManagedExtension(Profile* profile, const std::string& id) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!profile || profile->IsOffTheRecord()) return BOAZ_HOST_UNAVAILABLE;
  if (!ValidID(id)) return BOAZ_HOST_INVALID_ARGUMENT;
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* registrar = extensions::ExtensionRegistrar::Get(profile);
  if (!registry || !registrar) return BOAZ_HOST_UNAVAILABLE;
  const auto* extension = registry->disabled_extensions().GetByID(id);
  if (!extension) return BOAZ_HOST_INVALID_ARGUMENT;
  if (!CanEnable(profile, *extension)) return BOAZ_HOST_UNAVAILABLE;
  registrar->EnableExtension(id);
  return registry->enabled_extensions().GetByID(id) && !registry->disabled_extensions().GetByID(id)
             ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
}
BoazHostResult DisableManagedExtension(Profile* profile, const std::string& id) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!profile || profile->IsOffTheRecord()) return BOAZ_HOST_UNAVAILABLE;
  if (!ValidID(id)) return BOAZ_HOST_INVALID_ARGUMENT;
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* registrar = extensions::ExtensionRegistrar::Get(profile);
  if (!registry || !registrar) return BOAZ_HOST_UNAVAILABLE;
  const auto* extension = registry->enabled_extensions().GetByID(id);
  if (!extension) {
    return registry->disabled_extensions().GetByID(id) ? BOAZ_HOST_OK : BOAZ_HOST_INVALID_ARGUMENT;
  }
  if (!CanDisable(profile, *extension)) return BOAZ_HOST_UNAVAILABLE;
  registrar->DisableExtension(id, {extensions::disable_reason::DISABLE_USER_ACTION});
  return registry->disabled_extensions().GetByID(id) && !registry->enabled_extensions().GetByID(id)
             ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
}
}
