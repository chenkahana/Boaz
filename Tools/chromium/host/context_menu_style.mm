#import <AppKit/AppKit.h>
#include "context_menu_style.h"

#include <algorithm>
#include "base/check.h"
#include "chrome/app/chrome_command_ids.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/models/image_model.h"
#include "ui/events/event_constants.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/gfx/image/image.h"
#include "ui/menus/cocoa/text_services_context_menu.h"
#include "ui/menus/simple_menu_model.h"

namespace boaz {
namespace {
// Explain / Ask About This Page, added by native-context-menu.patch.
constexpr int kAskCommandId = 50900;
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
    {IDC_CONTENT_CONTEXT_LOOK_UP, "character.book.closed"},
    {IDC_SPELLCHECK_ADD_TO_DICTIONARY, "text.book.closed"},
    {ui::TextServicesContextMenu::kSpeechMenu, "speaker.wave.2"},
    {ui::TextServicesContextMenu::kWritingDirectionMenu, "arrow.left.arrow.right"},
};
}  // namespace

void StyleContextMenu(ui::SimpleMenuModel* menu) {
  for (size_t i = 0; i < menu->GetItemCount(); ++i) {
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
