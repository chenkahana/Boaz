#ifndef BOAZ_CHROMIUM_CONTEXT_MENU_STYLE_H_
#define BOAZ_CHROMIUM_CONTEXT_MENU_STYLE_H_
namespace ui { class SimpleMenuModel; }
namespace boaz {
// SF Symbol icons, and the shortcuts Boaz's menu bar really fires, for a page context menu's own items.
void StyleContextMenu(ui::SimpleMenuModel* menu);
}
#endif
