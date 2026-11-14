#include "page_print.h"
#include "printing/buildflags/buildflags.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#if BUILDFLAG(ENABLE_PRINTING) && BUILDFLAG(ENABLE_BASIC_PRINT_DIALOG)
#include "chrome/browser/printing/print_view_manager_common.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#endif
namespace boaz {
BoazHostResult PrintPage(content::WebContents* contents) {
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI))
    return BOAZ_HOST_WRONG_THREAD;
  if (!contents || contents->IsBeingDestroyed()) return BOAZ_HOST_INVALID_HANDLE;
  auto* frame = contents->GetPrimaryMainFrame();
  if (!frame || !frame->IsActive() || !frame->IsRenderFrameLive() || contents->IsCrashed())
    return BOAZ_HOST_UNAVAILABLE;
#if BUILDFLAG(ENABLE_PRINTING) && BUILDFLAG(ENABLE_BASIC_PRINT_DIALOG)
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  if (!browser || browser->GetTabStripModel()->GetActiveWebContents() != contents ||
      !chrome::CanPrint(browser) || !chrome::CanBasicPrint(browser))
    return BOAZ_HOST_UNAVAILABLE;
  return printing::StartPrint(contents, /*print_preview_disabled=*/true,
                              /*has_selection=*/false)
      ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
#else
  return BOAZ_HOST_UNAVAILABLE;
#endif
}
}
