#ifndef BOAZ_CHROMIUM_HOST_H_
#define BOAZ_CHROMIUM_HOST_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BOAZ_HOST_ABI_VERSION 1u

typedef uint64_t BoazHostWindow;
typedef uint64_t BoazHostPage;

typedef enum BoazHostResult {
  BOAZ_HOST_OK = 0,
  BOAZ_HOST_INVALID_ARGUMENT = 1,
  BOAZ_HOST_INVALID_HANDLE = 2,
  BOAZ_HOST_CLOSING = 3,
  BOAZ_HOST_WRONG_THREAD = 4,
  BOAZ_HOST_UNAVAILABLE = 5
} BoazHostResult;

typedef enum BoazHostPageEvent {
  BOAZ_HOST_PAGE_CREATED = 0,
  BOAZ_HOST_PAGE_CHANGED = 1,
  BOAZ_HOST_PAGE_CLOSING = 2,
  BOAZ_HOST_PAGE_CLOSE_CANCELLED = 3,
  BOAZ_HOST_PAGE_CLOSED = 4,
  BOAZ_HOST_PAGE_RENDERER_FAILED = 5
} BoazHostPageEvent;

/* Callback strings are borrowed UTF-8 and expire when the callback returns. */
typedef struct BoazHostPageState {
  size_t size;
  BoazHostPage page;
  BoazHostWindow window;
  uint64_t document_generation;
  const char* url;
  const char* title;
  int32_t extension_tab_id;
  int32_t extension_window_id;
  uint8_t loading;
  uint8_t can_go_back;
  uint8_t can_go_forward;
} BoazHostPageState;

typedef struct BoazHostCallbacks {
  size_t size;
  void* context;
  void (*page_event)(void* context, BoazHostPageEvent event,
                     const BoazHostPageState* state);
  void (*window_closed)(void* context, BoazHostWindow window);
  void (*shutdown_ready)(void* context);
} BoazHostCallbacks;

/* All calls and callbacks use Chromium's UI thread, also the AppKit main thread.
 * Handles are never reused during a process. Callbacks must not reenter the API;
 * enqueue commands on the next main-loop turn. */
typedef struct BoazHostAPI {
  size_t size;
  uint32_t version;
  BoazHostResult (*set_callbacks)(const BoazHostCallbacks* callbacks);
  BoazHostResult (*create_window)(void* native_nswindow,
                                  BoazHostWindow* window);
  BoazHostResult (*create_page)(BoazHostWindow window, const char* url,
                                BoazHostPage* page);
  BoazHostResult (*navigate)(BoazHostPage page, const char* url);
  BoazHostResult (*go_back)(BoazHostPage page);
  BoazHostResult (*go_forward)(BoazHostPage page);
  BoazHostResult (*reload)(BoazHostPage page);
  BoazHostResult (*activate_page)(BoazHostPage page, uint8_t focus);
  /* Borrowed NSView. Valid until PAGE_CLOSING; the UI must detach it then. */
  BoazHostResult (*get_native_view)(BoazHostPage page, void** native_nsview);
  BoazHostResult (*close_page)(BoazHostPage page);
  BoazHostResult (*close_window)(BoazHostWindow window);
  BoazHostResult (*request_shutdown)(void);
} BoazHostAPI;

/* Called once by the prototype host after its isolated profile is ready.
 * The table remains valid through shutdown_ready. No production profile opens. */
typedef BoazHostResult (*BoazNativeUIStart)(const BoazHostAPI* api);

#ifdef __cplusplus
}
#endif

#endif
