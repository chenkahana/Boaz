#ifndef BOAZ_CHROMIUM_PAGE_PRINT_H_
#define BOAZ_CHROMIUM_PAGE_PRINT_H_
#include "boaz_host.h"
namespace content { class WebContents; }
namespace boaz {
// UI-thread entry for an owned page. Success means Chromium accepted the print
// request, not that the user printed or saved a document.
BoazHostResult PrintPage(content::WebContents* contents);
}
#endif
