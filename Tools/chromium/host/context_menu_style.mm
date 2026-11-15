#import <AppKit/AppKit.h>
#include "context_menu_style.h"

#include <algorithm>
#include <utility>
#include "base/check.h"
#include "base/compiler_specific.h"
#include "base/containers/flat_map.h"
#include "base/containers/span.h"
#include "base/no_destructor.h"
#include "boaz_host.h"
#include "bootstrap.h"
#include "chrome/app/chrome_command_ids.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/models/image_model.h"
#include "ui/events/event_constants.h"
#include "ui/events/keycodes/keyboard_code_conversion_mac.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/gfx/image/image.h"
#include "ui/menus/cocoa/text_services_context_menu.h"
#include "ui/menus/simple_menu_model.h"

namespace boaz {
namespace {
// Explain / Ask About This Page, added by native-context-menu.patch.
constexpr int kAskCommandId = 50900;
// Search Image / Search Page with Google Lens, added by native-context-menu-search.patch.
constexpr int kLensImageCommandId = 50901;
constexpr int kLensPageCommandId = 50902;
constexpr int kCommand = ui::EF_COMMAND_DOWN;

struct Style {
  int id;
  const char* symbol;
  ui::KeyboardCode key = ui::VKEY_UNKNOWN;
  int modifiers = ui::EF_NONE;
};

// Shortcuts only where the menu bar fires the same key. Never ⌘S for Save: it toggles the sidebar.
constexpr Style kStyles[] = {
    {IDC_BACK, "chevron.backward"},
    {IDC_FORWARD, "chevron.forward"},
    {IDC_RELOAD, "arrow.clockwise"},
    {IDC_SAVE_PAGE, "square.and.arrow.down"},
    {IDC_PRINT, "printer", ui::VKEY_P, kCommand},
    {IDC_VIEW_SOURCE, "chevron.left.forwardslash.chevron.right"},
    {IDC_CONTENT_CONTEXT_VIEWFRAMESOURCE, "chevron.left.forwardslash.chevron.right"},
    {IDC_CONTENT_CONTEXT_EXIT_FULLSCREEN, "arrow.down.right.and.arrow.up.left"},
    {IDC_CONTENT_CONTEXT_INSPECTELEMENT, "wrench.and.screwdriver"},
    {kAskCommandId, "apple.intelligence"},
    {IDC_CONTENT_CONTEXT_OPENLINKNEWTAB, "plus.square.on.square"},
    {IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW, "macwindow.badge.plus"},
    {IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD, "eyeglasses"},
    {IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW, "rectangle.split.2x1"},
    {IDC_CONTENT_CONTEXT_SAVELINKAS, "square.and.arrow.down"},
    {IDC_CONTENT_CONTEXT_COPYLINKLOCATION, "link"},
    {IDC_CONTENT_CONTEXT_COPYLINKTEXT, "textformat"},
    {IDC_CONTENT_CONTEXT_COPYLINKTOTEXT, "link.badge.plus"},
    {IDC_CONTENT_CONTEXT_RESHARELINKTOTEXT, "link"},
    {IDC_CONTENT_CONTEXT_REMOVELINKTOTEXT, "minus.circle"},
    {IDC_CONTENT_CONTEXT_OPENIMAGENEWTAB, "plus.square.on.square"},
    {IDC_CONTENT_CONTEXT_SAVEIMAGEAS, "square.and.arrow.down"},
    {IDC_CONTENT_CONTEXT_COPYIMAGE, "doc.on.doc"},
    {IDC_CONTENT_CONTEXT_COPYIMAGELOCATION, "link"},
    {IDC_CONTENT_CONTEXT_GENERATE_QR_CODE, "qrcode"},
    {IDC_CONTENT_CONTEXT_OPENAVNEWTAB, "plus.square.on.square"},
    {IDC_CONTENT_CONTEXT_SAVEAVAS, "square.and.arrow.down"},
    {IDC_CONTENT_CONTEXT_COPYAVLOCATION, "link"},
    {IDC_CONTENT_CONTEXT_COPYVIDEOFRAME, "photo"},
    {IDC_CONTENT_CONTEXT_SAVEVIDEOFRAMEAS, "square.and.arrow.down"},
    {IDC_CONTENT_CONTEXT_LOOP, "repeat"},
    {IDC_CONTENT_CONTEXT_CONTROLS, "slider.horizontal.below.rectangle"},
    {IDC_CONTENT_CONTEXT_PICTUREINPICTURE, "pip.enter"},
    {IDC_CONTENT_CONTEXT_UNDO, "arrow.uturn.backward", ui::VKEY_Z, kCommand},
    {IDC_CONTENT_CONTEXT_REDO, "arrow.uturn.forward", ui::VKEY_Z, kCommand | ui::EF_SHIFT_DOWN},
    {IDC_CONTENT_CONTEXT_CUT, "scissors", ui::VKEY_X, kCommand},
    {IDC_CONTENT_CONTEXT_COPY, "doc.on.doc", ui::VKEY_C, kCommand},
    {IDC_CONTENT_CONTEXT_PASTE, "doc.on.clipboard", ui::VKEY_V, kCommand},
    {IDC_CONTENT_CONTEXT_PASTE_AND_MATCH_STYLE, "clipboard", ui::VKEY_V,
     kCommand | ui::EF_ALT_DOWN | ui::EF_SHIFT_DOWN},
    {IDC_CONTENT_CONTEXT_SELECTALL, "selection.pin.in.out", ui::VKEY_A, kCommand},
    {IDC_CONTENT_CONTEXT_EMOJI, "face.smiling", ui::VKEY_SPACE, kCommand | ui::EF_CONTROL_DOWN},
    {IDC_CONTENT_CONTEXT_SEARCHWEBFOR, "magnifyingglass"},
    {kLensImageCommandId, "camera.viewfinder"},
    {kLensPageCommandId, "camera.viewfinder"},
    {kSendToDevicesCommandId, "laptopcomputer.and.iphone"},
    {kShareCommandId, "square.and.arrow.up"},
    {kShareImageCommandId, "square.and.arrow.up"},
    {IDC_CONTENT_CONTEXT_LOOK_UP, "character.book.closed"},
    {IDC_SPELLCHECK_ADD_TO_DICTIONARY, "text.book.closed"},
    {ui::TextServicesContextMenu::kSpeechMenu, "speaker.wave.2"},
    {ui::TextServicesContextMenu::kWritingDirectionMenu, "arrow.left.arrow.right"},
};

constexpr std::pair<BoazHostMenuShortcutCommand, int> kRebindable[] = {
    {BOAZ_MENU_SHORTCUT_BACK, IDC_BACK},
    {BOAZ_MENU_SHORTCUT_FORWARD, IDC_FORWARD},
    {BOAZ_MENU_SHORTCUT_RELOAD, IDC_RELOAD},
    {BOAZ_MENU_SHORTCUT_VIEW_SOURCE, IDC_VIEW_SOURCE},
    {BOAZ_MENU_SHORTCUT_PICTURE_IN_PICTURE, IDC_CONTENT_CONTEXT_PICTUREINPICTURE},
};

// The rebindable commands' shortcuts, pushed from Boaz's key bindings.
base::flat_map<int, ui::Accelerator>& Rebound() {
  static base::NoDestructor<base::flat_map<int, ui::Accelerator>> shortcuts;
  return *shortcuts;
}

ui::KeyboardCode KeyCode(uint16_t key) {
  switch (key) {
    case NSLeftArrowFunctionKey: return ui::VKEY_LEFT;
    case NSRightArrowFunctionKey: return ui::VKEY_RIGHT;
    case NSUpArrowFunctionKey: return ui::VKEY_UP;
    case NSDownArrowFunctionKey: return ui::VKEY_DOWN;
    case '\t': return ui::VKEY_TAB;
    case '\r': return ui::VKEY_RETURN;
    case ' ': return ui::VKEY_SPACE;
    case 0x1B: return ui::VKEY_ESCAPE;
    case 0x08:
    case 0x7F: return ui::VKEY_BACK;
    default: return ui::KeyboardCodeFromCharCode(key);
  }
}
}  // namespace

bool SetContextMenuShortcuts(const BoazHostMenuShortcut* shortcuts, size_t count) {
  base::flat_map<int, ui::Accelerator> rebound;
  for (const auto& shortcut : UNSAFE_BUFFERS(base::span(shortcuts, count))) {
    const auto command =
        std::ranges::find(kRebindable, shortcut.command, &std::pair<BoazHostMenuShortcutCommand, int>::first);
    if (command == std::ranges::end(kRebindable)) {
      return false;
    }
    const ui::KeyboardCode key = KeyCode(shortcut.key);
    if (key == ui::VKEY_UNKNOWN) {
      continue;  // A key Chromium can't name shows no shortcut.
    }
    int modifiers = ui::EF_NONE;
    if (shortcut.modifiers & NSEventModifierFlagCommand) modifiers |= ui::EF_COMMAND_DOWN;
    if (shortcut.modifiers & NSEventModifierFlagShift) modifiers |= ui::EF_SHIFT_DOWN;
    if (shortcut.modifiers & NSEventModifierFlagOption) modifiers |= ui::EF_ALT_DOWN;
    if (shortcut.modifiers & NSEventModifierFlagControl) modifiers |= ui::EF_CONTROL_DOWN;
    rebound.insert_or_assign(command->second, ui::Accelerator(key, modifiers));
  }
  Rebound() = std::move(rebound);
  return true;
}

void StyleContextMenu(ui::SimpleMenuModel* menu) {
  for (size_t i = 0; i < menu->GetItemCount(); ++i) {
    if (const auto rebound = Rebound().find(menu->GetCommandIdAt(i)); rebound != Rebound().end()) {
      menu->SetAcceleratorAt(i, rebound->second);
      menu->SetForceShowAcceleratorForItemAt(i, true);
    }
    const auto style = std::ranges::find(kStyles, menu->GetCommandIdAt(i), &Style::id);
    if (style == std::ranges::end(kStyles)) {
      continue;
    }
    NSImage* image = [NSImage imageWithSystemSymbolName:@(style->symbol) accessibilityDescription:nil];
    DCHECK(image) << style->symbol;
    if (image) {
      menu->SetIcon(i, ui::ImageModel::FromImage(gfx::Image(image)));
    }
    if (style->key != ui::VKEY_UNKNOWN) {
      menu->SetAcceleratorAt(i, ui::Accelerator(style->key, style->modifiers));
      menu->SetForceShowAcceleratorForItemAt(i, true);
    }
  }
}
}  // namespace boaz
