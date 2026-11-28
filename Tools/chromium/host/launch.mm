#include "boaz/launch.h"

#import <Foundation/Foundation.h>

#include <string>

#include "base/apple/bundle_locations.h"
#include "base/check.h"
#include "base/check_op.h"
#include "base/command_line.h"

namespace boaz {
std::optional<base::FilePath> PackagedApplicationUserDataPath() {
  @autoreleasepool {
    NSBundle* bundle = base::apple::OuterBundle();
    NSString* identifier = bundle.bundleIdentifier;
    const bool development = [identifier isEqualToString:@"com.chenkahana.boaz.chromium.dev"];
    const bool production = [identifier isEqualToString:@"com.chenkahana.boaz"];
    id marker = [bundle objectForInfoDictionaryKey:@"BoazNativeApplication"];
    if (!marker && !development && !production) return std::nullopt;
    CHECK([marker isKindOfClass:[NSNumber class]] && [marker boolValue]);
    CHECK(development || production);
    NSString* expected_channel = development ? @"development" : @"production";
    id channel = [bundle objectForInfoDictionaryKey:@"BoazDistributionChannel"];
    CHECK([channel isKindOfClass:[NSString class]] && [channel isEqualToString:expected_channel]);
    NSString* product = development ? @"Boaz Chromium Development" : @"Boaz/Chromium";
    id configured_product = [bundle objectForInfoDictionaryKey:@"CrProductDirName"];
    CHECK([configured_product isKindOfClass:[NSString class]] && [configured_product isEqualToString:product]);
    NSArray<NSURL*>* roots = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                  inDomains:NSUserDomainMask];
    CHECK_EQ(roots.count, 1u);
    NSURL* path = [roots.firstObject URLByAppendingPathComponent:product isDirectory:YES];
    CHECK(path.isFileURL);
    base::FilePath result(path.fileSystemRepresentation);
    CHECK(result.IsAbsolute());
    return result;
  }
}

void ConfigurePackagedApplicationLaunch() {
  auto* command = base::CommandLine::ForCurrentProcess();
  if (command->HasSwitch("type")) return;
  const auto expected = PackagedApplicationUserDataPath();
  if (!expected) return;
  if (command->HasSwitch("user-data-dir")) {
    CHECK(command->GetSwitchValuePath("user-data-dir").StripTrailingSeparators() == *expected);
  }
  if (command->HasSwitch("profile-directory")) {
    CHECK_EQ(command->GetSwitchValueASCII("profile-directory"), "Default");
  }
  for (const char* name : {"remote-debugging-port", "remote-debugging-pipe",
                           "remote-allow-origins", "remote-debugging-address",
                           "custom-devtools-frontend"}) {
    command->RemoveSwitch(name);
  }
  command->AppendSwitch("boaz-native-host");
  command->AppendSwitch("boaz-app-ui");
  command->AppendSwitch("no-startup-window");
  command->AppendSwitch("no-first-run");
  command->AppendSwitchASCII("profile-directory", "Default");
  command->AppendSwitchPath("user-data-dir", *expected);
  // The field-trial testing config that unofficial builds apply turns the first two on; Chrome ships them off.
  // Omnibox Everywhere puts Chromium's magnifying glass in the menu bar, and UnoPhase2FollowUp shows Google's
  // "Sync history" sign-in card on chrome://history. The other two contact Google at launch, before any
  // browsing: NetworkTimeServiceQuerying only improves the wording on clock-related certificate errors (Chromium
  // falls back to its build-time check), and PreconnectToSearch preconnects to Chromium's default engine before
  // Boaz's set_default_search_provider switches it to DuckDuckGo (PLAN-05's launch-time network pass).
  constexpr char kDisabledFeatures[] =
      "OmniboxEverywhere,UnoPhase2FollowUp,NetworkTimeServiceQuerying,PreconnectToSearch";
  std::string disabled = command->GetSwitchValueASCII("disable-features");
  command->AppendSwitchASCII("disable-features",
                             disabled.empty() ? kDisabledFeatures : disabled + "," + kDisabledFeatures);
}
}  // namespace boaz
