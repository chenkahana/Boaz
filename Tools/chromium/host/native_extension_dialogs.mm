#import <AppKit/AppKit.h>
#include "native_extension_dialogs.h"
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/global_error/global_error.h"
#include "chrome/browser/ui/global_error/global_error_observer.h"
#include "chrome/browser/ui/global_error/global_error_service.h"
#include "chrome/browser/ui/global_error/global_error_service_factory.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/models/dialog_model.h"
#include "ui/base/models/dialog_model_field.h"
#include "ui/base/models/dialog_model_host.h"
#include "ui/base/models/image_model.h"
#include "ui/events/event.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/image/image.h"
#include "ui/strings/grit/ui_strings.h"

@interface BoazDialogAction : NSObject
@property(nonatomic, copy) void (^handler)(id sender);
- (void)run:(id)sender;
@end
@implementation BoazDialogAction
@synthesize handler = _handler;
- (void)run:(id)sender { if (self.handler) self.handler(sender); }
@end

namespace boaz {
namespace {
void CheckUI() {
  CHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK([NSThread isMainThread]);
}
NSString* Text(const std::u16string& text) { return base::SysUTF16ToNSString(text); }
ui::KeyEvent ActivationEvent() { return ui::KeyEvent(ui::EventType::kKeyPressed, ui::VKEY_RETURN, ui::EF_NONE); }

// What a label says, its links' text substituted in, as views shows it.
std::u16string LabelText(const ui::DialogModelLabel& label) {
  if (label.replacements().empty()) return label.GetString();
  std::vector<std::u16string> texts;
  for (const auto& replacement : label.replacements()) texts.push_back(replacement.text());
  return l10n_util::GetStringFUTF16(label.message_id(), texts, nullptr);
}
bool Supported(const std::vector<std::unique_ptr<ui::DialogModelField>>& fields) {
  for (const auto& field : fields) {
    switch (field->type()) {
      case ui::DialogModelField::kParagraph:
      case ui::DialogModelField::kCheckbox:
      case ui::DialogModelField::kMenuItem:
      case ui::DialogModelField::kSeparator:
      // A views-only custom field: in extension dialogs, the Google account sign-in promo Boaz has no account for.
      case ui::DialogModelField::kCustom:
        break;
      case ui::DialogModelField::kSection:
        if (!Supported(static_cast<ui::DialogModelSection*>(field.get())->fields())) return false;
        break;
      default:
        return false;
    }
  }
  return true;
}
NSTextField* Label(NSString* text, NSFont* font, NSColor* color) {
  NSTextField* label = [NSTextField wrappingLabelWithString:text];
  label.font = font;
  label.textColor = color;
  label.preferredMaxLayoutWidth = 320;
  label.selectable = NO;
  return label;
}

// A ui::DialogModel drawn in an NSPopover at the extension's button, as Chrome's bubble points at it.
class PopoverDialog final : public ui::DialogModelHost, public ui::DialogModelFieldHost {
 public:
  static bool CanShow(ui::DialogModel& model) { return Supported(model.fields(DialogModelHost::GetPassKey())); }
  PopoverDialog(std::unique_ptr<ui::DialogModel> model, NSView* anchor, NSRect bounds)
      : model_(std::move(model)) {
    model_->set_host(DialogModelHost::GetPassKey(), this);
    actions_ = [[NSMutableArray alloc] init];
    NSStackView* stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    stack.identifier = @"screen.extensionDialog";
    // Chrome's bubbles are a fixed width; wrapping labels alone would let the stack collapse to nothing.
    [stack.widthAnchor constraintEqualToConstant:352].active = YES;
    NSStackView* header = [[NSStackView alloc] init];
    header.spacing = 10;
    const ui::ImageModel& icon = model_->icon(DialogModelHost::GetPassKey());
    if (icon.IsImage() && !icon.GetImage().IsEmpty()) {
      NSImageView* image = [NSImageView imageViewWithImage:icon.GetImage().ToNSImage()];
      [image.widthAnchor constraintEqualToConstant:32].active = YES;
      [image.heightAnchor constraintEqualToConstant:32].active = YES;
      [header addArrangedSubview:image];
    }
    const std::u16string& title = model_->title(DialogModelHost::GetPassKey());
    if (!title.empty())
      [header addArrangedSubview:Label(Text(title), [NSFont boldSystemFontOfSize:13], NSColor.labelColor)];
    if (header.arrangedSubviews.count) [stack addArrangedSubview:header];
    const std::u16string& subtitle = model_->subtitle(DialogModelHost::GetPassKey());
    if (!subtitle.empty())
      [stack addArrangedSubview:Label(Text(subtitle), [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor)];
    AddFields(stack, model_->fields(DialogModelHost::GetPassKey()));
    if (const auto& footnote = model_->footnote_label())
      [stack addArrangedSubview:Label(Text(LabelText(*footnote)), [NSFont systemFontOfSize:11],
                                      NSColor.secondaryLabelColor)];
    AddButtons(stack);
    NSViewController* controller = [[NSViewController alloc] init];
    controller.view = stack;
    popover_ = [[NSPopover alloc] init];
    popover_.contentViewController = controller;
    popover_.behavior = model_->close_on_deactivate(DialogModelHost::GetPassKey())
        ? NSPopoverBehaviorTransient : NSPopoverBehaviorApplicationDefined;
    popover_.animates = NO;
    auto* self = this;
    closed_observer_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSPopoverDidCloseNotification
        object:popover_ queue:nil usingBlock:^(NSNotification*) { self->Dismissed(); }];
    [popover_ showRelativeToRect:bounds ofView:anchor
                   preferredEdge:anchor.isFlipped ? NSRectEdgeMaxY : NSRectEdgeMinY];
  }
  void Close() override {
    CheckUI();
    if (closed_) return;
    closed_ = true;
    if (closed_observer_) [[NSNotificationCenter defaultCenter] removeObserver:closed_observer_];
    closed_observer_ = nil;
    for (BoazDialogAction* action in actions_) action.handler = nil;
    [popover_ close];
    popover_ = nil;
    model_->OnDialogDestroying(DialogModelHost::GetPassKey());
    model_.reset();
    base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }
  void OnDialogButtonChanged() override {}
  ~PopoverDialog() = default;

 private:
  BoazDialogAction* Action(void (^handler)(id)) {
    BoazDialogAction* action = [[BoazDialogAction alloc] init];
    action.handler = handler;
    [actions_ addObject:action];
    return action;
  }
  void AddFields(NSStackView* stack, const std::vector<std::unique_ptr<ui::DialogModelField>>& fields) {
    auto* self = this;
    for (const auto& field : fields) {
      if (!field->is_visible()) continue;
      switch (field->type()) {
        case ui::DialogModelField::kParagraph: {
          auto* paragraph = field->AsParagraph();
          if (!paragraph->header().empty())
            [stack addArrangedSubview:Label(Text(paragraph->header()), [NSFont boldSystemFontOfSize:12],
                                            NSColor.labelColor)];
          const auto& label = paragraph->label();
          [stack addArrangedSubview:Label(Text(LabelText(label)), [NSFont systemFontOfSize:12],
              label.is_secondary() ? NSColor.secondaryLabelColor : NSColor.labelColor)];
          // Links in the text become link buttons below it.
          for (const auto& replacement : label.replacements()) {
            if (!replacement.callback()) continue;
            auto callback = *replacement.callback();
            BoazDialogAction* action = Action(^(id) {
              if (self->closed_) return;
              callback.Run(ActivationEvent());
            });
            NSButton* link = [NSButton buttonWithTitle:Text(replacement.text()) target:action action:@selector(run:)];
            link.bordered = NO;
            link.contentTintColor = NSColor.linkColor;
            [stack addArrangedSubview:link];
          }
          break;
        }
        case ui::DialogModelField::kCheckbox: {
          auto* checkbox = field->AsCheckbox();
          BoazDialogAction* action = Action(^(id sender) {
            if (self->closed_) return;
            checkbox->OnChecked(DialogModelFieldHost::GetPassKey(),
                                [(NSButton*)sender state] == NSControlStateValueOn);
          });
          NSButton* button = [NSButton checkboxWithTitle:Text(LabelText(checkbox->label())) target:action
                                                  action:@selector(run:)];
          button.state = checkbox->is_checked() ? NSControlStateValueOn : NSControlStateValueOff;
          [stack addArrangedSubview:button];
          break;
        }
        case ui::DialogModelField::kMenuItem: {
          auto* item = field->AsMenuItem();
          BoazDialogAction* action = Action(^(id) {
            if (self->closed_) return;
            item->OnActivated(DialogModelFieldHost::GetPassKey(), 0);
          });
          NSButton* button = [NSButton buttonWithTitle:Text(item->label()) target:action action:@selector(run:)];
          button.bordered = NO;
          button.alignment = NSTextAlignmentLeft;
          button.enabled = item->is_enabled();
          if (item->icon().IsImage() && !item->icon().GetImage().IsEmpty()) {
            NSImage* image = item->icon().GetImage().ToNSImage();
            image.size = NSMakeSize(16, 16);
            button.image = image;
            button.imagePosition = NSImageLeading;
          }
          [stack addArrangedSubview:button];
          break;
        }
        case ui::DialogModelField::kSeparator: {
          NSBox* separator = [[NSBox alloc] init];
          separator.boxType = NSBoxSeparator;
          [stack addArrangedSubview:separator];
          [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32].active = YES;
          break;
        }
        case ui::DialogModelField::kSection:
          AddFields(stack, static_cast<ui::DialogModelSection*>(field.get())->fields());
          break;
        default:
          break;
      }
    }
  }
  void AddButtons(NSStackView* stack) {
    auto* self = this;
    auto* ok = model_->ok_button(DialogModelHost::GetPassKey());
    auto* cancel = model_->cancel_button(DialogModelHost::GetPassKey());
    auto* extra = model_->extra_button(DialogModelHost::GetPassKey());
    if (!ok && !cancel && !extra) return;
    NSStackView* row = [[NSStackView alloc] init];
    row.spacing = 8;
    if (extra) {
      BoazDialogAction* action = Action(^(id) {
        if (!self->closed_) extra->OnPressed(DialogModelHost::GetPassKey(), ActivationEvent());
      });
      NSButton* button = [NSButton buttonWithTitle:Text(extra->label()) target:action action:@selector(run:)];
      button.enabled = extra->is_enabled();
      [row addArrangedSubview:button];
    }
    [row addArrangedSubview:[[NSView alloc] init]];
    if (cancel) {
      BoazDialogAction* action = Action(^(id) {
        if (!self->closed_ && self->model_->OnDialogCancelAction(DialogModelHost::GetPassKey())) self->Close();
      });
      NSButton* button = [NSButton buttonWithTitle:Text(cancel->label().empty()
          ? l10n_util::GetStringUTF16(IDS_APP_CANCEL) : cancel->label()) target:action action:@selector(run:)];
      button.keyEquivalent = @"\e";
      button.enabled = cancel->is_enabled();
      button.identifier = @"control.extensionDialog.cancel";
      [row addArrangedSubview:button];
    }
    if (ok) {
      BoazDialogAction* action = Action(^(id) {
        if (!self->closed_ && self->model_->OnDialogAcceptAction(DialogModelHost::GetPassKey())) self->Close();
      });
      NSButton* button = [NSButton buttonWithTitle:Text(ok->label().empty()
          ? l10n_util::GetStringUTF16(IDS_APP_OK) : ok->label()) target:action action:@selector(run:)];
      button.keyEquivalent = @"\r";
      button.enabled = ok->is_enabled();
      button.identifier = @"control.extensionDialog.ok";
      [row addArrangedSubview:button];
    }
    [stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32].active = YES;
  }
  // The user dismissed the popover (a click outside or Esc).
  void Dismissed() {
    if (closed_) return;
    model_->OnDialogCloseAction(DialogModelHost::GetPassKey());
    Close();
  }

  std::unique_ptr<ui::DialogModel> model_;
  NSPopover* __strong popover_ = nil;
  NSMutableArray* __strong actions_ = nil;
  id closed_observer_ = nil;
  bool closed_ = false;
};

NSWindow* SheetParent(content::WebContents* contents) {
  if (!contents) return nil;
  NSWindow* window = contents->GetTopLevelNativeWindow().GetNativeNSWindow();
  return window && window.visible && !window.attachedSheet ? window : nil;
}

class GlobalErrors final : public NativeGlobalErrors, public GlobalErrorObserver {
 public:
  explicit GlobalErrors(BrowserWindowInterface* browser) : browser_(browser->GetWeakPtr()) {
    if (auto* service = GlobalErrorServiceFactory::GetForProfile(browser->GetProfile()))
      observation_.Observe(service);
    NSWindow* window = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    auto weak = weak_.GetWeakPtr();
    key_observer_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification
        object:window queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
      if (weak) weak->ShowPending();
    }];
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<GlobalErrors> self) { if (self) self->ShowPending(); }, weak));
  }
  ~GlobalErrors() override {
    if (key_observer_) [[NSNotificationCenter defaultCenter] removeObserver:key_observer_];
  }
  void OnGlobalErrorsChanged() override {
    // Not from inside the service's notification.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<GlobalErrors> self) { if (self) self->ShowPending(); }, weak_.GetWeakPtr()));
  }

 private:
  void ShowPending() {
    if (!browser_ || !observation_.IsObserving() || !browser_->GetWindow()) return;
    NSWindow* window = browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    if (!browser_->GetWindow()->IsActive() || window.attachedSheet) return;
    if (auto* error = observation_.GetSource()->GetFirstGlobalErrorWithBubbleView())
      error->ShowBubbleView(browser_.get());
  }
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::ScopedObservation<GlobalErrorService, GlobalErrorObserver> observation_{this};
  id key_observer_ = nil;
  base::WeakPtrFactory<GlobalErrors> weak_{this};
};
}  // namespace

bool ShowNativeExtensionDialog(gfx::NativeWindow parent, const std::vector<std::string>& extension_ids,
                               std::unique_ptr<ui::DialogModel>& model) {
  CheckUI();
  NSWindow* window = parent.GetNativeNSWindow();
  if (!model || !window || !PopoverDialog::CanShow(*model)) return false;
  void* view = nullptr;
  gfx::Rect bounds;
  if (FindNativeExtensionAnchor((__bridge void*)window, extension_ids, &view, &bounds)) {
    new PopoverDialog(std::move(model), (__bridge NSView*)view,
                      NSMakeRect(bounds.x(), bounds.y(), bounds.width(), bounds.height()));
    return true;
  }
  // No extension button on screen (a popup or DevTools window, a hidden sidebar): point at the window's
  // top trailing corner, where Chrome's toolbar would be, rather than Chromium's views dialogs.
  NSView* content = window.contentView;
  if (!content) return false;
  const NSRect frame = content.bounds;
  const CGFloat top = content.isFlipped ? NSMinY(frame) + 12 : NSMaxY(frame) - 12;
  new PopoverDialog(std::move(model), content, NSMakeRect(NSMaxX(frame) - 40, top, 1, 1));
  return true;
}

void ShowNativeExtensionInstallError(content::WebContents* contents, const std::u16string& message) {
  CheckUI();
  NSWindow* window = SheetParent(contents);
  if (!window || message.empty()) return;
  NSAlert* alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleWarning;
  alert.messageText = Text(message);
  [alert addButtonWithTitle:Text(l10n_util::GetStringUTF16(IDS_APP_OK))];
  alert.window.identifier = @"screen.extensionInstallError";
  [alert beginSheetModalForWindow:window completionHandler:nil];
}

bool ShowNativeGlobalErrorBubble(BrowserWindowInterface* browser,
                                 base::WeakPtr<GlobalErrorWithStandardBubble> error) {
  CheckUI();
  if (!browser || !error || !browser->GetWindow()) return false;
  NSWindow* window = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
  if (!window || !window.visible || window.attachedSheet) return false;
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = Text(error->GetBubbleViewTitle());
  std::vector<std::u16string> messages = error->GetBubbleViewMessages();
  alert.informativeText = Text(base::JoinString(messages, u"\n"));
  const std::u16string accept = error->GetBubbleViewAcceptButtonLabel();
  const std::u16string cancel = error->GetBubbleViewCancelButtonLabel();
  enum Choice { kAccept, kCancel, kClose };
  std::vector<Choice> choices;
  if (!accept.empty()) { [alert addButtonWithTitle:Text(accept)]; choices.push_back(kAccept); }
  if (!cancel.empty()) { [alert addButtonWithTitle:Text(cancel)]; choices.push_back(kCancel); }
  if (error->ShouldShowCloseButton() || choices.empty()) {
    [alert addButtonWithTitle:Text(l10n_util::GetStringUTF16(IDS_APP_CLOSE))].keyEquivalent = @"\e";
    choices.push_back(kClose);
  }
  alert.window.identifier = @"screen.extensionGlobalError";
  auto weak_browser = browser->GetWeakPtr();
  [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    const size_t index = static_cast<size_t>(response - NSAlertFirstButtonReturn);
    const Choice choice = index < choices.size() ? choices[index] : kClose;
    // After AppKit has finished the sheet: the buttons open other sheets (the permission and removal prompts).
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<GlobalErrorWithStandardBubble> error, base::WeakPtr<BrowserWindowInterface> browser,
           Choice choice) {
          if (!error || !browser) return;
          if (choice == kAccept) error->BubbleViewAcceptButtonPressed(browser.get());
          else if (choice == kCancel) error->BubbleViewCancelButtonPressed(browser.get());
          if (error) error->BubbleViewDidClose(browser.get());
        }, error, weak_browser, choice));
  }];
  return true;
}

std::unique_ptr<NativeGlobalErrors> NativeGlobalErrors::Create(BrowserWindowInterface* browser) {
  return std::make_unique<GlobalErrors>(browser);
}
}  // namespace boaz
