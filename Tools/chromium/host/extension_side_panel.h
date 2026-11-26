#ifndef BOAZ_CHROMIUM_EXTENSION_SIDE_PANEL_H_
#define BOAZ_CHROMIUM_EXTENSION_SIDE_PANEL_H_
#include <memory>
#include <optional>
#include <string>
#include "base/callback_list.h"
#include "base/functional/callback.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
class BrowserWindowInterface;
namespace boaz {
// The window's side panel, as Chromium's extension code drives it (sidePanel.open, openPanelOnActionClick, the
// action menu's Open side panel, sidePanel.close). It shows extension panels only; Boaz hosts the page's view at
// the window's trailing edge. Other side panel entries (bookmarks, reading list, Lens) aren't Boaz's and stay closed.
class NativeSidePanel final : public SidePanelUI {
 public:
  using Presenter = base::RepeatingCallback<void(void* nsview, const std::string& title)>;
  NativeSidePanel(BrowserWindowInterface* browser, Presenter presenter);
  ~NativeSidePanel() override;
  // Closes the panel as the user closing it does (sidePanel.onClosed).
  void Close();

  void Show(SidePanelEntryId entry_id, std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override;
  void Show(SidePanelEntryKey entry_key, std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override;
  void ShowFrom(SidePanelEntryKey entry_key, gfx::Rect starting_bounds_in_browser_coordinates) override;
  void Close(SidePanelEntryHideReason hide_reason, bool suppress_animations) override;
  void Toggle(SidePanelEntryKey key, SidePanelOpenTrigger open_trigger) override;
  std::optional<SidePanelEntryId> GetCurrentEntryId() const override;
  int GetCurrentEntryDefaultContentWidth() const override;
  void OverrideContentsWidth(int width) override;
  void ResetContentsWidthOverride() override;
  bool IsSidePanelShowing() const override;
  bool IsSidePanelEntryShowing(const SidePanelEntryKey& entry_key) const override;
  bool IsSidePanelEntryShowing(const SidePanelEntryKey& entry_key, bool for_tab) const override;
  base::CallbackListSubscription RegisterSidePanelShown(ShownCallback callback) override;
  void OnActiveTabChanged(content::WebContents* old_contents, content::WebContents* new_contents,
                          bool tab_removed_for_deletion) override;
  content::WebContents* GetWebContentsForTest(SidePanelEntryId id) override;
  void DisableAnimationsForTesting() override {}
  void SetNoDelaysForTesting(bool) override {}
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
#endif
