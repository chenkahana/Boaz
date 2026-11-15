#import <AppKit/AppKit.h>
#include "extension_actions.h"
#include "boaz_host.h"
#include "extension_popup.h"
#include "extension_side_panel.h"
#include <algorithm>
#include <map>
#include <optional>
#include <set>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/current_thread.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_commands_global_registry.h"
#include "chrome/browser/extensions/extension_context_menu_model.h"
#include "chrome/browser/extensions/extension_keybinding_registry.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_delegate.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/extensions/extensions_toolbar_view_model.h"
#include "chrome/browser/ui/extensions/settings_api_bubble_helpers.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/api/extension_action/action_info.h"
#include "extensions/common/command.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/base_window.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
#include "ui/color/color_provider.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
#include "ui/events/event_constants.h"
#include "ui/events/keycodes/keyboard_code_conversion_mac.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/menus/cocoa/menu_controller.h"

namespace boaz {
namespace {
void CheckUI() {
  CHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK([NSThread isMainThread]);
}
// Boaz draws a 26-point button; Chromium draws the icon and its badge into it.
constexpr int kActionSize = 26;

// Extension keyboard commands in a Boaz window, as Chrome's toolbar registers them: named commands raise
// commands.onCommand, and _execute_action runs the toolbar action. Accelerators are checked on every key press in
// the window and its child panels, ahead of the page, as Chrome's high-priority extension accelerators are.
class KeybindingRegistry final : public extensions::ExtensionKeybindingRegistry {
 public:
  KeybindingRegistry(BrowserWindowInterface* browser, ExtensionsToolbarViewModel* toolbar)
      : ExtensionKeybindingRegistry(browser->GetProfile(), TabListInterface::From(browser),
                                    ExtensionKeybindingRegistry::ALL_EXTENSIONS),
        profile_(browser->GetProfile()), toolbar_(toolbar) {
    window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    Init();
    auto weak = weak_factory_.GetWeakPtr();
    monitor_ = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent*(NSEvent* event) {
      return weak && weak->Handle(event) ? nil : event;
    }];
    observers_ = [[NSMutableArray alloc] init];
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification]) {
      [observers_ addObject:[[NSNotificationCenter defaultCenter] addObserverForName:name object:window_
          queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* notification) {
        if (weak) weak->SetActive([notification.name isEqualToString:NSWindowDidBecomeKeyNotification]);
      }]];
    }
    if (window_.keyWindow) SetActive(true);
  }
  ~KeybindingRegistry() override {
    if (monitor_) [NSEvent removeMonitor:monitor_];
    for (id token in observers_) [[NSNotificationCenter defaultCenter] removeObserver:token];
    SetActive(false);
  }

 private:
  void SetActive(bool active) {
    auto* global = extensions::ExtensionCommandsGlobalRegistry::Get(profile_);
    if (!global) return;
    if (active) global->set_registry_for_active_window(this);
    else if (global->registry_for_active_window() == this) global->set_registry_for_active_window(nullptr);
  }
  bool PopulateCommands(const extensions::Extension* extension, ui::CommandMap* commands) override {
    auto* service = extensions::CommandService::Get(browser_context());
    const bool named = service->GetNamedCommands(extension->id(), extensions::CommandService::ACTIVE,
        extensions::CommandService::REGULAR, commands);
    extensions::Command command;
    const bool action = service->GetExtensionActionCommand(extension->id(),
        extensions::ActionInfo::Type::kAction, extensions::CommandService::ACTIVE, &command, nullptr);
    if (action) (*commands)[command.command_name()] = command;
    return named || action;
  }
  bool RegisterAccelerator(const ui::Accelerator& accelerator, const extensions::ExtensionId& id,
                           const std::string& command) override {
    active_.insert(accelerator);
    if (extensions::Command::IsActionRelatedCommand(command)) action_accelerators_[accelerator] = id;
    return true;
  }
  void UnregisterAccelerator(const ui::Accelerator& accelerator) override {
    active_.erase(accelerator);
    action_accelerators_.erase(accelerator);
  }
  void OnShortcutHandlingSuspended(bool suspended) override { suspended_ = suspended; }
  // The action's command is handled here too, not by each button.
  bool ShouldIgnoreCommand(const std::string&) const override { return false; }
  bool Handle(NSEvent* event) {
    CheckUI();
    if (suspended_ || event.type != NSEventTypeKeyDown || event.ARepeat || !window_) return false;
    NSWindow* target = event.window;
    if (target != window_ && target.parentWindow != window_) return false;
    constexpr int kModifiers = ui::EF_SHIFT_DOWN | ui::EF_CONTROL_DOWN | ui::EF_ALT_DOWN | ui::EF_COMMAND_DOWN;
    const ui::Accelerator accelerator(ui::KeyboardCodeFromNSEvent(event),
                                      ui::EventFlagsFromModifiers(event.modifierFlags) & kModifiers);
    if (!active_.contains(accelerator)) return false;
    if (auto it = action_accelerators_.find(accelerator); it != action_accelerators_.end()) {
      auto* model = toolbar_->GetActionModelForId(it->second);
      return model && model->CanHandleAccelerators() && model->TryHandleAcceleratorPress();
    }
    return NotifyEventTargets(accelerator);
  }

  raw_ptr<Profile> profile_;
  raw_ptr<ExtensionsToolbarViewModel> toolbar_;
  NSWindow* __weak window_ = nil;
  id monitor_ = nil;
  NSMutableArray* __strong observers_ = nil;
  std::set<ui::Accelerator> active_;
  std::map<ui::Accelerator, extensions::ExtensionId> action_accelerators_;
  bool suspended_ = false;
  base::WeakPtrFactory<KeybindingRegistry> weak_factory_{this};
};
}  // namespace

class NativeExtensionActions::Impl final : public ExtensionsToolbarViewModel::Delegate,
                                           public ExtensionsToolbarViewModel::Observer {
 public:
  class ActionDelegate final : public ExtensionActionDelegate {
   public:
    ActionDelegate(Impl* owner, std::string id) : owner_(owner), id_(std::move(id)) {}
    void AttachToModel(ExtensionActionViewModel*) override {}
    void DetachFromModel() override { owner_->ClosePopupFor(id_); }
    void RegisterCommand() override {}
    void UnregisterCommand() override {}
    bool IsShowingPopup() const override { return owner_->IsShowingPopupFor(id_); }
    void HidePopup() override { owner_->ClosePopupFor(id_); }
    gfx::NativeView GetPopupNativeViewForTesting() override { return owner_->PopupNativeView(); }
    void TriggerPopup(std::unique_ptr<extensions::ExtensionViewHost> host, PopupShowAction action,
                      bool by_user, ShowPopupCallback callback) override {
      owner_->ShowPopup(id_, std::move(host), action, std::move(callback));
    }
    // An action with nothing to run on this page shows its menu, as Chrome's does.
    void ShowContextMenuAsFallback() override { owner_->ShowMenuAtAnchor(id_); }
    void CloseExtensionsMenuIfOpen() override {}
   private:
    raw_ptr<Impl> owner_;
    std::string id_;
  };

  Impl(BrowserWindowInterface* browser, base::RepeatingClosure changed, AnchorProvider anchor,
       SidePanelPresenter side_panel)
      : browser_(browser), changed_(std::move(changed)), anchor_(std::move(anchor)) {
    CheckUI();
    CHECK(browser);
    side_panel_ = std::make_unique<NativeSidePanel>(browser, std::move(side_panel));
    side_panel_data_.emplace(browser->GetUnownedUserDataHost(), *side_panel_);
    auto* model = ToolbarActionsModel::Get(browser->GetProfile());
    if (!model || !ToolbarActionsModel::CanShowActionsInToolbar(*browser)) return;
    toolbar_ = std::make_unique<ExtensionsToolbarViewModel>(this, browser, model);
    container_data_.emplace(browser->GetUnownedUserDataHost(), *toolbar_);
    toolbar_observation_.Observe(toolbar_.get());
    registry_ = std::make_unique<KeybindingRegistry>(browser, toolbar_.get());
    if (toolbar_->AreActionsInitialized()) OnActionsInitialized();
  }
  ~Impl() override {
    CheckUI();
    closing_ = true;
    changed_.Reset();
    icon_subscriptions_.clear();
    Close();
    popup_.reset();
    menu_ = nil;
    registry_.reset();
    toolbar_observation_.Reset();
    container_data_.reset();
    toolbar_.reset();
    side_panel_data_.reset();
    side_panel_.reset();
  }

  // ExtensionsToolbarViewModel::Delegate
  std::unique_ptr<ExtensionActionViewModel> CreateActionViewModel(const ToolbarActionsModel::ActionId& id,
                                                                  ExtensionsContainer*) override {
    return ExtensionActionViewModel::Create(id, browser_, std::make_unique<ActionDelegate>(this, id));
  }
  void HideActivePopup() override { Close(); }
  void CloseExtensionsMenuIfOpen() override {}
  bool CanShowToolbarActionPopupForAPICall(const ToolbarActionsModel::ActionId&) override {
    return !closing_ && !IsShowingPopup() && browser_->GetWindow() && browser_->GetWindow()->IsActive();
  }
  void ToggleExtensionsMenu() override {}

  // ExtensionsToolbarViewModel::Observer
  void OnActionsInitialized() override {
    for (const auto& id : toolbar_->GetAllActionIds()) ObserveIcon(id);
    Changed();
  }
  void OnActionAdded(const ToolbarActionsModel::ActionId& id) override { ObserveIcon(id); Changed(); }
  void OnActionRemoved(const ToolbarActionsModel::ActionId& id) override {
    icon_subscriptions_.erase(id);
    ClosePopupFor(id);
    Changed();
  }
  void OnActionUpdated(const ToolbarActionsModel::ActionId&) override { Changed(); }
  void OnPinnedActionsChanged() override { Changed(); }
  void OnActiveWebContentsChanged(bool is_same_document, content::WebContents* contents) override {
    Changed();
    if (contents && !is_same_document) extensions::MaybeShowExtensionControlledNewTabPage(browser_, contents);
  }
  void OnRequestAccessButtonParamsChanged(content::WebContents*) override { Changed(); }
  void OnToolbarControlStateUpdated() override { Changed(); }

  Result Validate(content::WebContents* expected) const {
    CheckUI();
    auto* tab = browser_->GetActiveTabInterface();
    if (!expected || !tab || tab->GetContents() != expected ||
        expected->GetBrowserContext() != browser_->GetProfile()) return Result::kInvalidTarget;
    if (!toolbar_ || closing_) return Result::kUnavailable;
    return Result::kOk;
  }
  ToolbarActionViewModel* Model(const std::string& id) const {
    return toolbar_ && toolbar_->GetAllActionIds().contains(id) ? toolbar_->GetActionModelForId(id) : nullptr;
  }
  Result GetActions(content::WebContents* expected, std::vector<Action>* output) const {
    output->clear();
    if (auto result = Validate(expected); result != Result::kOk) return result;
    if (!toolbar_->AreActionsInitialized()) return Result::kOk;
    auto* actions_model = ToolbarActionsModel::Get(browser_->GetProfile());
    const auto requests = toolbar_->GetRequestAccessButtonParams(expected).extension_ids;
    std::vector<std::string> ordered;
    for (const auto& id : toolbar_->GetPinnedActionIds())
      if (toolbar_->GetAllActionIds().contains(id)) ordered.push_back(id);
    std::vector<Action> pinned;
    std::vector<Action> rest;
    for (const auto& id : toolbar_->GetAllActionIds()) {
      auto* model = toolbar_->GetActionModelForId(id);
      if (!model) continue;
      Action action{id, base::UTF16ToUTF8(model->GetActionName()), 0};
      if (actions_model->IsActionPinned(id)) action.flags |= BOAZ_EXTENSION_PINNED;
      if (actions_model->IsActionForcePinned(id)) action.flags |= BOAZ_EXTENSION_FORCE_PINNED;
      if (model->IsEnabled(expected)) action.flags |= BOAZ_EXTENSION_ENABLED;
      if (std::ranges::find(requests, id) != requests.end()) action.flags |= BOAZ_EXTENSION_REQUESTS_ACCESS;
      if (std::ranges::find(ordered, id) != ordered.end()) pinned.push_back(std::move(action));
      else rest.push_back(std::move(action));
    }
    // Pinned in Chromium's order, then the rest by name, as Chrome's extensions menu lists them.
    std::ranges::sort(pinned, {}, [&](const Action& a) { return std::ranges::find(ordered, a.id) - ordered.begin(); });
    std::ranges::sort(rest, [](const Action& a, const Action& b) {
      return base::ToLowerASCII(a.name) < base::ToLowerASCII(b.name); });
    *output = std::move(pinned);
    output->insert(output->end(), rest.begin(), rest.end());
    return Result::kOk;
  }
  Result GetMetadata(content::WebContents* expected, const std::string& id, Metadata* output) const {
    *output = {};
    if (auto result = Validate(expected); result != Result::kOk) return result;
    auto* model = Model(id);
    auto* registry = extensions::ExtensionRegistry::Get(browser_->GetProfile());
    auto* extension = registry ? registry->enabled_extensions().GetByID(id) : nullptr;
    auto* action = extension ? extensions::ExtensionActionManager::Get(browser_->GetProfile())
        ->GetExtensionAction(*extension) : nullptr;
    const int tab_id = extensions::ExtensionTabUtil::GetTabId(expected);
    if (!model || !action || tab_id < 0) return Result::kUnavailable;
    Metadata metadata{base::UTF16ToUTF8(model->GetActionTitle(expected)), action->GetDisplayBadgeText(tab_id), {}};
    if (metadata.title.size() > 4096 || metadata.badge_text.size() > 256 ||
        !base::IsStringUTF8(metadata.title) || !base::IsStringUTF8(metadata.badge_text) ||
        metadata.title.find('\0') != std::string::npos ||
        metadata.badge_text.find('\0') != std::string::npos) return Result::kUnsupported;
    // Chromium's own toolbar icon: the badge in its colors, greyed out where the action can't run.
    const gfx::ImageSkia image = model->GetIcon(expected, gfx::Size(kActionSize, kActionSize))
        .Rasterize(&expected->GetColorProvider());
    if (!image.isNull()) {
      const auto& bitmap = image.GetRepresentation(2.0f).GetBitmap();
      if (bitmap.width() == 2 * kActionSize && bitmap.height() == 2 * kActionSize) {
        auto encoded = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, false);
        if (encoded && encoded->size() <= 256 * 1024) metadata.icon_png = std::move(*encoded);
      }
    }
    *output = std::move(metadata);
    return Result::kOk;
  }
  Result Invoke(content::WebContents* expected, const std::string& id, void* anchor, const gfx::Rect& bounds) {
    if (auto result = Validate(expected); result != Result::kOk) return result;
    if (invoking_) return Result::kUnavailable;
    if (!AnchorValid((__bridge NSView*)anchor, bounds)) return Result::kInvalidAnchor;
    if (!Model(id)) return Result::kUnavailable;
    invoke_anchor_ = (__bridge NSView*)anchor;
    invoke_bounds_ = bounds;
    invoking_ = true;
    toolbar_->ExecuteUserAction(id, ToolbarActionViewModel::InvocationSource::kToolbarButton);
    invoking_ = false;
    invoke_anchor_ = nil;
    return Result::kOk;
  }
  Result SetPinned(const std::string& id, bool pinned) {
    CheckUI();
    auto* model = ToolbarActionsModel::Get(browser_->GetProfile());
    if (!toolbar_ || !model || !Model(id)) return Result::kUnavailable;
    if (browser_->GetProfile()->IsOffTheRecord() || model->IsActionForcePinned(id)) return Result::kUnsupported;
    if (model->IsActionPinned(id) != pinned) model->SetActionVisibility(id, pinned);
    return Result::kOk;
  }
  Result ShowMenu(content::WebContents* expected, const std::string& id, void* anchor, const gfx::Rect& bounds) {
    if (auto result = Validate(expected); result != Result::kOk) return result;
    if (!AnchorValid((__bridge NSView*)anchor, bounds)) return Result::kInvalidAnchor;
    if (!Model(id) || menu_) return Result::kUnavailable;
    PostMenu(id, (__bridge NSView*)anchor, bounds);
    return Result::kOk;
  }
  void ShowMenuAtAnchor(const std::string& id) {
    if (closing_ || menu_) return;
    NSView* view = invoke_anchor_;
    gfx::Rect bounds = invoke_bounds_;
    if (!view) {
      void* found = nullptr;
      if (!anchor_.Run(id, &found, &bounds)) return;
      view = (__bridge NSView*)found;
    }
    if (AnchorValid(view, bounds)) PostMenu(id, view, bounds);
  }
  Result GetAccessRequest(content::WebContents* expected, AccessRequest* output) const {
    *output = {};
    if (auto result = Validate(expected); result != Result::kOk) return result;
    auto params = toolbar_->GetRequestAccessButtonParams(expected);
    output->tooltip = base::UTF16ToUTF8(params.tooltip_text);
    output->extension_ids = std::move(params.extension_ids);
    return Result::kOk;
  }
  Result GrantAccessRequest(content::WebContents* expected) {
    if (auto result = Validate(expected); result != Result::kOk) return result;
    auto params = toolbar_->GetRequestAccessButtonParams(expected);
    if (params.extension_ids.empty()) return Result::kUnavailable;
    toolbar_->GrantSiteAccess(expected, params.extension_ids, params.origin);
    return Result::kOk;
  }
  void CloseSidePanel() { if (side_panel_) side_panel_->Close(); }
  bool GetAnchor(const std::vector<std::string>& ids, void** view, gfx::Rect* bounds) const {
    if (closing_) return false;
    if (ids.size() == 1 && anchor_.Run(ids[0], view, bounds)) return true;
    return anchor_.Run(std::string(), view, bounds);
  }
  void Close() {
    CheckUI();
    auto popup = std::move(popup_);
    popup_id_.clear();
    if (popup) popup->Close();
  }
  bool IsShowingPopup() const { return popup_ && popup_->IsShowing(); }
  bool IsShowingPopupFor(const std::string& id) const { return popup_id_ == id && IsShowingPopup(); }
  void ClosePopupFor(const std::string& id) { if (popup_id_ == id) Close(); }
  gfx::NativeView PopupNativeView() const { return popup_ ? popup_->GetNativeView() : gfx::NativeView(); }
  void ShowPopup(const std::string& id, std::unique_ptr<extensions::ExtensionViewHost> host,
                 PopupShowAction action, ShowPopupCallback callback) {
    NSView* view = invoke_anchor_;
    gfx::Rect bounds = invoke_bounds_;
    if (!view) {
      void* found = nullptr;
      if (!closing_) anchor_.Run(id, &found, &bounds);
      view = (__bridge NSView*)found;
    }
    Close();
    if (!closing_ && AnchorValid(view, bounds))
      popup_ = NativeExtensionPopup::Create(std::move(host), browser_, (__bridge void*)view, bounds, action,
                                            std::move(callback));
    else if (callback)
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(std::move(callback), nullptr));
    if (popup_) popup_id_ = id;
  }

 private:
  void Changed() { if (changed_) changed_.Run(); }
  void ObserveIcon(const std::string& id) {
    if (auto* model = toolbar_->GetActionModelForId(id))
      icon_subscriptions_[id] = model->RegisterIconUpdateObserver(
          base::BindRepeating(&Impl::Changed, weak_factory_.GetWeakPtr()));
  }
  bool AnchorValid(NSView* view, const gfx::Rect& bounds) const {
    return view && [view isKindOfClass:[NSView class]] && browser_->GetWindow() && view.window &&
        view.window == browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() && !bounds.IsEmpty();
  }
  // Runs after the API call returns: the menu's loop runs tasks, and Boaz's caller isn't reentrant.
  void PostMenu(const std::string& id, NSView* view, const gfx::Rect& bounds) {
    NSView* __weak weak_view = view;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<Impl> self, std::string id, NSView* __weak view, gfx::Rect bounds) {
          NSView* strong = view;
          if (self && strong) self->RunMenu(id, strong, bounds);
        }, weak_factory_.GetWeakPtr(), id, weak_view, bounds));
  }
  void RunMenu(const std::string& id, NSView* view, const gfx::Rect& bounds) {
    CheckUI();
    auto* model = Model(id);
    if (closing_ || menu_ || !model || !AnchorValid(view, bounds)) return;
    ui::MenuModel* menu = model->GetContextMenu(
        extensions::ExtensionContextMenuModel::ContextMenuSource::kToolbarAction);
    if (!menu) return;
    MenuControllerCocoa* controller = [[MenuControllerCocoa alloc] initWithModel:menu isContextMenu:YES
                                                                       delegate:nil];
    menu_ = controller;
    controller.menu.identifier = @"control.extensionMenu";
    const NSPoint point = NSMakePoint(bounds.x(), view.isFlipped ? bounds.bottom() : bounds.y());
    auto weak = weak_factory_.GetWeakPtr();
    {
      base::CurrentThread::ScopedAllowApplicationTasksInNativeNestedLoop allow;
      [controller.menu popUpMenuPositioningItem:nil atLocation:point inView:view];
    }
    if (weak) menu_ = nil;
  }

  raw_ptr<BrowserWindowInterface> browser_;
  base::RepeatingClosure changed_;
  AnchorProvider anchor_;
  std::unique_ptr<NativeSidePanel> side_panel_;
  std::optional<ui::ScopedUnownedUserData<SidePanelUI>> side_panel_data_;
  std::unique_ptr<ExtensionsToolbarViewModel> toolbar_;
  std::optional<ui::ScopedUnownedUserData<ExtensionsContainer>> container_data_;
  base::ScopedObservation<ExtensionsToolbarViewModel, ExtensionsToolbarViewModel::Observer>
      toolbar_observation_{this};
  std::unique_ptr<KeybindingRegistry> registry_;
  std::map<std::string, base::CallbackListSubscription> icon_subscriptions_;
  std::unique_ptr<NativeExtensionPopup> popup_;
  std::string popup_id_;
  MenuControllerCocoa* __strong menu_ = nil;
  NSView* __weak invoke_anchor_ = nil;
  gfx::Rect invoke_bounds_;
  bool invoking_ = false;
  bool closing_ = false;
  base::WeakPtrFactory<Impl> weak_factory_{this};
};

NativeExtensionActions::NativeExtensionActions(BrowserWindowInterface* browser, base::RepeatingClosure changed,
    AnchorProvider anchor, SidePanelPresenter side_panel)
    : impl_(std::make_unique<Impl>(browser, std::move(changed), std::move(anchor), std::move(side_panel))) {}
NativeExtensionActions::~NativeExtensionActions() = default;
NativeExtensionActions::Result NativeExtensionActions::GetActions(content::WebContents* contents,
    std::vector<Action>* output) const { return impl_->GetActions(contents, output); }
NativeExtensionActions::Result NativeExtensionActions::GetMetadata(
    content::WebContents* contents, const std::string& id, Metadata* output) const {
  return impl_->GetMetadata(contents, id, output);
}
NativeExtensionActions::Result NativeExtensionActions::Invoke(content::WebContents* contents,
    const std::string& id, void* anchor, const gfx::Rect& bounds) {
  return impl_->Invoke(contents, id, anchor, bounds);
}
NativeExtensionActions::Result NativeExtensionActions::SetPinned(const std::string& id, bool pinned) {
  return impl_->SetPinned(id, pinned);
}
NativeExtensionActions::Result NativeExtensionActions::ShowMenu(content::WebContents* contents,
    const std::string& id, void* anchor, const gfx::Rect& bounds) {
  return impl_->ShowMenu(contents, id, anchor, bounds);
}
NativeExtensionActions::Result NativeExtensionActions::GetAccessRequest(content::WebContents* contents,
    AccessRequest* output) const { return impl_->GetAccessRequest(contents, output); }
NativeExtensionActions::Result NativeExtensionActions::GrantAccessRequest(content::WebContents* contents) {
  return impl_->GrantAccessRequest(contents);
}
void NativeExtensionActions::CloseSidePanel() { impl_->CloseSidePanel(); }
bool NativeExtensionActions::GetAnchor(const std::vector<std::string>& ids, void** view,
                                       gfx::Rect* bounds) const {
  return impl_->GetAnchor(ids, view, bounds);
}
void NativeExtensionActions::ClosePopup() { impl_->Close(); }
}
