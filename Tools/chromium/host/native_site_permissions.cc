#include "native_site_permissions.h"
#include <optional>
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/permissions/permission_decision_auto_blocker_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/permissions/permission_decision_auto_blocker.h"
#include "components/permissions/permission_util.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/permission_controller_delegate.h"
#include "third_party/blink/public/common/permissions/permission_utils.h"
#include "third_party/blink/public/mojom/permissions/permission.mojom.h"
#include "url/origin.h"
namespace boaz {
namespace {
struct Types {
  ContentSettingsType content;
  blink::PermissionType permission;
  blink::mojom::PermissionName name;
};
std::optional<Types> GetTypes(SitePermissionKind kind) {
  switch (kind) {
    case SitePermissionKind::kCamera: return Types{ContentSettingsType::MEDIASTREAM_CAMERA, blink::PermissionType::VIDEO_CAPTURE, blink::mojom::PermissionName::VIDEO_CAPTURE};
    case SitePermissionKind::kMicrophone: return Types{ContentSettingsType::MEDIASTREAM_MIC, blink::PermissionType::AUDIO_CAPTURE, blink::mojom::PermissionName::AUDIO_CAPTURE};
    case SitePermissionKind::kNotifications: return Types{ContentSettingsType::NOTIFICATIONS, blink::PermissionType::NOTIFICATIONS, blink::mojom::PermissionName::NOTIFICATIONS};
  }
  return std::nullopt;
}
bool Valid(Profile* profile, const url::Origin& requesting, const url::Origin& embedding) {
  return profile && !profile->ShutdownStarted() && !requesting.opaque() && !embedding.opaque() &&
      requesting.GetURL().SchemeIsHTTPOrHTTPS() && embedding.GetURL().SchemeIsHTTPOrHTTPS();
}
std::optional<PermissionState> Read(Profile* profile, const url::Origin& requesting,
                                    const url::Origin& embedding, SitePermissionKind kind) {
  const auto types = GetTypes(kind);
  if (!types) return std::nullopt;
  auto* map = HostContentSettingsMapFactory::GetForProfile(profile);
  auto* blocker = PermissionDecisionAutoBlockerFactory::GetForProfile(profile);
  auto* delegate = profile->GetPermissionControllerDelegate();
  if (!map || !blocker || !delegate) return std::nullopt;
  const GURL canonical = permissions::PermissionUtil::GetCanonicalOrigin(
      types->content, requesting.GetURL(), embedding.GetURL());
  content_settings::SettingInfo info;
  map->GetContentSetting(canonical, embedding.GetURL(), types->content, &info);
  auto descriptor = blink::mojom::PermissionDescriptor::New();
  descriptor->name = types->name;
  const auto status = delegate->GetPermissionStatus(descriptor, requesting.GetURL(), embedding.GetURL());
  PermissionState::Setting setting = PermissionState::Setting::kOther;
  switch (status) {
    case blink::mojom::PermissionStatus::ASK: setting = PermissionState::Setting::kAsk; break;
    case blink::mojom::PermissionStatus::GRANTED: setting = PermissionState::Setting::kAllow; break;
    case blink::mojom::PermissionStatus::DENIED: setting = PermissionState::Setting::kBlock; break;
  }
  const bool editable = info.source == content_settings::SettingSource::kUser ||
                        info.source == content_settings::SettingSource::kNone;
  return PermissionState{kind, setting, editable,
                         blocker->GetEmbargoResult(canonical, types->content).has_value()};
}
}
std::vector<PermissionState> ReadSitePermissions(Profile* profile, const url::Origin& requesting,
                                               const url::Origin& embedding) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!Valid(profile, requesting, embedding)) return {};
  std::vector<PermissionState> result;
  for (auto kind : {SitePermissionKind::kCamera, SitePermissionKind::kMicrophone, SitePermissionKind::kNotifications}) {
    auto state = Read(profile, requesting, embedding, kind);
    if (!state) return {};
    result.push_back(*state);
  }
  return result;
}
BoazHostResult ResetSitePermission(Profile* profile, const url::Origin& requesting,
                                  const url::Origin& embedding, SitePermissionKind kind) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!Valid(profile, requesting, embedding) || !GetTypes(kind)) return BOAZ_HOST_INVALID_ARGUMENT;
  auto before = Read(profile, requesting, embedding, kind);
  if (!before || !before->can_reset) return BOAZ_HOST_UNAVAILABLE;
  const auto types = *GetTypes(kind);
  const GURL canonical = permissions::PermissionUtil::GetCanonicalOrigin(
      types.content, requesting.GetURL(), embedding.GetURL());
  profile->GetPermissionControllerDelegate()->ResetPermission(types.permission, requesting.GetURL(), embedding.GetURL());
  PermissionDecisionAutoBlockerFactory::GetForProfile(profile)->RemoveEmbargoAndResetCounts(canonical, types.content);
  auto after = Read(profile, requesting, embedding, kind);
  // Global defaults and device restrictions can still produce Allow or Block.
  return after && !after->embargoed ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
}
}
