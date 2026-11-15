#ifndef BOAZ_CHROMIUM_EXTENSION_ACTIONS_H_
#define BOAZ_CHROMIUM_EXTENSION_ACTIONS_H_
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include "base/functional/callback.h"
#include "ui/gfx/geometry/rect.h"
class BrowserWindowInterface;
namespace content { class WebContents; }
namespace boaz {
// A Boaz window's extension toolbar: Chromium's platform-neutral toolbar model (the ExtensionsContainer that
// chrome.action.openPopup, install feedback and commands use), its keyboard commands, popups and side panel. Boaz
// draws the buttons; Chromium decides what they do. UI thread only.
class NativeExtensionActions {
 public:
  enum class Result { kOk, kInvalidTarget, kUnavailable, kInvalidAnchor, kUnsupported };
  struct Action { std::string id; std::string name; uint32_t flags = 0; };
  struct Metadata { std::string title; std::string badge_text; std::vector<uint8_t> icon_png; };
  struct AccessRequest { std::string tooltip; std::vector<std::string> extension_ids; };
  // The shown button for an extension, or the extensions button for an empty id: a borrowed NSView and its bounds.
  using AnchorProvider = base::RepeatingCallback<bool(const std::string& id, void** nsview, gfx::Rect* bounds)>;
  // Shows (nsview) or removes (null) the side panel's view.
  using SidePanelPresenter = base::RepeatingCallback<void(void* nsview, const std::string& title)>;
  NativeExtensionActions(BrowserWindowInterface* browser, base::RepeatingClosure changed,
                         AnchorProvider anchor, SidePanelPresenter side_panel);
  ~NativeExtensionActions();
  Result GetActions(content::WebContents* expected_active, std::vector<Action>* output) const;
  Result GetMetadata(content::WebContents* expected_active, const std::string& extension_id,
                     Metadata* output) const;
  // Only call directly from a real native action-button activation.
  Result Invoke(content::WebContents* expected_active, const std::string& extension_id,
                void* anchor_nsview, const gfx::Rect& anchor_bounds);
  Result SetPinned(const std::string& extension_id, bool pinned);
  // Only call directly from a real native activation.
  Result ShowMenu(content::WebContents* expected_active, const std::string& extension_id,
                  void* anchor_nsview, const gfx::Rect& anchor_bounds);
  Result GetAccessRequest(content::WebContents* expected_active, AccessRequest* output) const;
  Result GrantAccessRequest(content::WebContents* expected_active);
  void CloseSidePanel();
  // Where a dialog for these extensions points (one extension's button, else the extensions button).
  bool GetAnchor(const std::vector<std::string>& extension_ids, void** nsview, gfx::Rect* bounds) const;
  void ClosePopup();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
#endif
