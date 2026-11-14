#ifndef BOAZ_ADBLOCK_NAVIGATION_H_
#define BOAZ_ADBLOCK_NAVIGATION_H_
namespace content { class NavigationThrottleRegistry; }
namespace boaz {
void AddAdblockNavigationThrottle(content::NavigationThrottleRegistry&);
}
#endif
