#ifndef BOAZ_CHROMIUM_EXTENSION_MANAGEMENT_H_
#define BOAZ_CHROMIUM_EXTENSION_MANAGEMENT_H_
#include <string>
#include <vector>
#include "boaz_host.h"
class Profile;
namespace boaz {
struct ManagedExtension {
  std::string id;
  std::string name;
  std::string version;
  bool enabled;
  bool can_disable;
  bool can_enable;
  bool can_uninstall;
};
std::vector<ManagedExtension> ListManagedExtensions(Profile* profile);
BoazHostResult EnableManagedExtension(Profile* profile, const std::string& id);
BoazHostResult DisableManagedExtension(Profile* profile, const std::string& id);
BoazHostResult UninstallManagedExtension(Profile* profile, const std::string& id);
}
#endif
