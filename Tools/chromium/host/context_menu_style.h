#ifndef BOAZ_CHROMIUM_CONTEXT_MENU_STYLE_H_
#define BOAZ_CHROMIUM_CONTEXT_MENU_STYLE_H_
#include <stddef.h>
struct BoazHostMenuShortcut;
namespace ui { class SimpleMenuModel; }
namespace boaz {
// SF Symbol icons, and the shortcuts Boaz's menu bar really fires, for a page context menu's own items.
void StyleContextMenu(ui::SimpleMenuModel* menu);
// Replaces the rebindable shortcuts (Back, Forward, Reload, View Source, Picture in Picture) pushed from Boaz's key
// bindings. False, with the table unchanged, for an unknown command.
bool SetContextMenuShortcuts(const BoazHostMenuShortcut* shortcuts, size_t count);
}
#endif
