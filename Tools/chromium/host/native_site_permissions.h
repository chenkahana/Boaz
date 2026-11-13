#ifndef BOAZ_NATIVE_SITE_PERMISSIONS_H_
#define BOAZ_NATIVE_SITE_PERMISSIONS_H_
#include <vector>
#include "boaz_host.h"
class Profile;
namespace url { class Origin; }
namespace boaz {
enum class SitePermissionKind { kCamera, kMicrophone, kNotifications };
struct PermissionState {
  enum class Setting { kAsk, kAllow, kBlock, kOther };
  SitePermissionKind kind;
  Setting setting;
  bool can_reset;
  bool embargoed;
};
std::vector<PermissionState> ReadSitePermissions(Profile*, const url::Origin& requesting,
                                               const url::Origin& embedding);
// Resetting a saved permission may require reload to end an active media stream.
BoazHostResult ResetSitePermission(Profile*, const url::Origin& requesting,
                                  const url::Origin& embedding, SitePermissionKind);
}
#endif
