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
};
std::vector<ManagedExtension> ListManagedExtensions(Profile* profile);
BoazHostResult DisableManagedExtension(Profile* profile, const std::string& id);
}
#endif
