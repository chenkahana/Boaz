#ifndef BOAZ_CHROMIUM_HOST_H_
#define BOAZ_CHROMIUM_HOST_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BOAZ_HOST_ABI_VERSION 6u

typedef uint64_t BoazHostWindow;
typedef uint64_t BoazHostPage;
typedef uint64_t BoazHostDocument;
typedef enum BoazHostScriptStatus {
  BOAZ_SCRIPT_SUCCESS, BOAZ_SCRIPT_INVALID_TARGET, BOAZ_SCRIPT_NAVIGATION,
  BOAZ_SCRIPT_CLOSED, BOAZ_SCRIPT_RENDERER_FAILED, BOAZ_SCRIPT_TIMEOUT,
  BOAZ_SCRIPT_INVALID_ARGUMENT, BOAZ_SCRIPT_BUSY
} BoazHostScriptStatus;
/* Posted once for accepted operations. JSON is borrowed during callback only;
 * failures have no result. Callbacks cannot reenter the host API. */
typedef void (*BoazHostScriptCompletion)(void* context, BoazHostPage page,
    BoazHostDocument document, BoazHostScriptStatus status, const char* result_json);

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
  BOAZ_HOST_PAGE_RENDERER_FAILED = 5,
  BOAZ_HOST_PAGE_VIEW_WILL_CHANGE = 6,
  BOAZ_HOST_PAGE_VIEW_CHANGED = 7
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
  uint8_t active;
} BoazHostPageState;

typedef struct BoazHostWindowLayout {
  size_t size;
  BoazHostWindow window;
  BoazHostPage first;
  BoazHostPage second;
  BoazHostPage active;
  uint8_t vertical;
  uint8_t content_fullscreen;
  double first_ratio;
} BoazHostWindowLayout;

/* Native UI owns these objects through window_closed. Service callbacks are
 * synchronous, must not reenter the API, and may only update native UI.
 * The event is a borrowed NSEvent, valid only during handle_key. */
typedef struct BoazHostWindowOptions {
  size_t size;
  void* native_nswindow;
  void* context;
  void* (*content_view)(void* context);
  void* (*address_field)(void* context);
  void (*focus_address)(void* context);
  void (*focus_toolbar)(void* context);
  uint8_t (*handle_key)(void* context, void* native_nsevent);
  void (*exclusive_access_notice)(void* context, const char* text,
                                  uint8_t visible);
} BoazHostWindowOptions;

typedef struct BoazHostCallbacks {
  size_t size;
  void* context;
  void (*page_event)(void* context, BoazHostPageEvent event,
                     const BoazHostPageState* state);
  BoazHostResult (*prepare_window)(void* context, BoazHostWindowOptions* options);
  void (*window_created)(void* context, BoazHostWindow window,
                         void* window_context);
  void (*window_closed)(void* context, BoazHostWindow window);
  void (*shutdown_ready)(void* context);
} BoazHostCallbacks;

/* Enumeration values are borrowed for the visitor call. Visitors must copy
 * strings and must not reenter the API. Only enabled profile actions appear. */
typedef void (*BoazHostExtensionVisitor)(void* context, const char* extension_id,
                                        const char* name);

/* All calls and callbacks use Chromium's UI thread, also the AppKit main thread.
 * Handles are never reused during a process. Callbacks must not reenter the API.
 * PAGE_CLOSING and PAGE_VIEW_WILL_CHANGE are synchronous and permit only
 * native-view detachment. Other events wait until model mutation unwinds. */
typedef struct BoazHostAPI {
  size_t size;
  uint32_t version;
  BoazHostResult (*set_callbacks)(const BoazHostCallbacks* callbacks);
  BoazHostResult (*create_window)(const BoazHostWindowOptions* options,
                                  BoazHostWindow* window);
  BoazHostResult (*create_page)(BoazHostWindow window, const char* url,
                                BoazHostPage* page);
  BoazHostResult (*navigate)(BoazHostPage page, const char* url);
  BoazHostResult (*go_back)(BoazHostPage page);
  BoazHostResult (*go_forward)(BoazHostPage page);
  BoazHostResult (*reload)(BoazHostPage page);
  BoazHostResult (*activate_page)(BoazHostPage page, uint8_t focus);
  /* Borrowed NSView. Detach on PAGE_CLOSING or PAGE_VIEW_WILL_CHANGE. */
  BoazHostResult (*get_native_view)(BoazHostPage page, void** native_nsview);
  BoazHostResult (*close_page)(BoazHostPage page);
  BoazHostResult (*close_window)(BoazHostWindow window);
  BoazHostResult (*request_shutdown)(void);
  BoazHostResult (*enumerate_extensions)(BoazHostWindow window,
      BoazHostExtensionVisitor visitor, void* context);
  /* Invoke only from real user activation. Anchor is a borrowed NSView in this
   * window; bounds use its local coordinates. Expected page must be active. */
  BoazHostResult (*invoke_extension)(BoazHostWindow window, BoazHostPage page,
      const char* extension_id, void* anchor_nsview,
      int32_t x, int32_t y, int32_t width, int32_t height);
  /* Capture before authentication. Accepted execution consumes the opaque document token.
   * Function source must be trusted app code; arguments are a JSON dictionary.
   * Return OK promises one completion before shutdown_ready, including failure.
   * Other immediate return values promise no completion. */
  BoazHostResult (*capture_document)(BoazHostPage page, BoazHostDocument* document);
  BoazHostResult (*release_document)(BoazHostPage page, BoazHostDocument document);
  BoazHostResult (*execute_trusted)(BoazHostPage page, BoazHostDocument document,
      const char* function_utf8, size_t function_length,
      const char* arguments_json, size_t arguments_length,
      BoazHostScriptCompletion completion, void* context);
  /* Layout is Chromium model state. Attach the outer native views for its
   * foreground pages; native attachment/hiding owns renderer visibility. */
  BoazHostResult (*get_window_layout)(BoazHostWindow window, BoazHostWindowLayout* layout);
  BoazHostResult (*set_split)(BoazHostWindow window, BoazHostPage first,
      BoazHostPage second, uint8_t vertical, double first_ratio);
  BoazHostResult (*clear_split)(BoazHostWindow window);
} BoazHostAPI;

/* Called once by the prototype host after its isolated profile is ready.
 * The table remains valid through shutdown_ready. No production profile opens. */
typedef BoazHostResult (*BoazNativeUIStart)(const BoazHostAPI* api);

#ifdef __cplusplus
}
#endif

#endif
