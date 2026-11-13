#ifndef BOAZ_CHROMIUM_HOST_H_
#define BOAZ_CHROMIUM_HOST_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BOAZ_HOST_ABI_VERSION 44u

typedef enum BoazHostDevToolsAction {
  BOAZ_DEVTOOLS_SHOW, BOAZ_DEVTOOLS_CONSOLE, BOAZ_DEVTOOLS_INSPECT,
  BOAZ_DEVTOOLS_STORAGE, BOAZ_DEVTOOLS_PERFORMANCE, BOAZ_DEVTOOLS_LIGHTHOUSE
} BoazHostDevToolsAction;
typedef enum BoazHostWindowRole {
  BOAZ_WINDOW_BROWSING, BOAZ_WINDOW_DEVTOOLS
} BoazHostWindowRole;
typedef uint64_t BoazHostWindow;
typedef uint64_t BoazHostPage;
typedef uint64_t BoazHostDocument;
typedef uint64_t BoazHostProfile;
typedef struct BoazHostViewport {
  int32_t width, height;
  double dpr;
  uint8_t mobile, touch, landscape;
  int32_t max_touch_points;
} BoazHostViewport;
/* Media: 0 screen, 1 print. Preferences: 0 system, 1 first, 2 second.
 * First/second: light/dark, no-preference/reduce, no-preference/more.
 * Vision: none, blurredVision, reducedContrast, achromatopsia,
 * deuteranopia, protanopia, tritanopia (0...6). */
typedef struct BoazHostMedia {
  int32_t type, color_scheme, reduced_motion, contrast, vision;
  uint8_t forced_colors;
} BoazHostMedia;
typedef struct BoazHostNetwork {
  double latency_ms, download_bytes_per_second, upload_bytes_per_second;
  uint8_t offline;
} BoazHostNetwork;
typedef struct BoazHostSensors {
  double latitude, longitude, accuracy;
  uint8_t has_location;
  const char* timezone;
  size_t timezone_length;
  const char* locale;
  size_t locale_length;
} BoazHostSensors;
typedef enum BoazHostEmulationStatus {
  BOAZ_EMULATION_SUCCESS, BOAZ_EMULATION_INVALID, BOAZ_EMULATION_UNAVAILABLE,
  BOAZ_EMULATION_PROTOCOL_ERROR, BOAZ_EMULATION_TIMEOUT,
  BOAZ_EMULATION_NAVIGATION, BOAZ_EMULATION_CLOSED
} BoazHostEmulationStatus;
typedef void (*BoazHostEmulationCompletion)(void* context, BoazHostPage page,
    uint64_t request, BoazHostEmulationStatus status);
/* Synchronous borrowed native defaults. Metadata JSON has Chromium's typed UA metadata fields. */
typedef void (*BoazHostUserAgentVisitor)(void* context, const char* user_agent,
    const char* navigator_platform, const char* metadata_json);
typedef enum BoazHostCaptureStatus {
  BOAZ_CAPTURE_SUCCESS, BOAZ_CAPTURE_INVALID_TARGET, BOAZ_CAPTURE_NAVIGATION,
  BOAZ_CAPTURE_CLOSED, BOAZ_CAPTURE_RENDERER_FAILED, BOAZ_CAPTURE_TIMEOUT,
  BOAZ_CAPTURE_BUSY, BOAZ_CAPTURE_TOO_LARGE, BOAZ_CAPTURE_FAILED, BOAZ_CAPTURE_CANCELLED
} BoazHostCaptureStatus;
/* Accepted requests complete once, posted on the UI thread. PNG bytes are borrowed
 * during this callback only, at most 8 MiB. Failure supplies no bytes. */
typedef void (*BoazHostCaptureCompletion)(void* context, BoazHostPage page,
    uint64_t request, BoazHostCaptureStatus status, const uint8_t* png, size_t size);
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

typedef void (*BoazHostProfileCompletion)(void* context, BoazHostResult result,
                                          BoazHostProfile profile);

typedef enum BoazHostCacheStatus { BOAZ_CACHE_SUCCESS, BOAZ_CACHE_FAILED } BoazHostCacheStatus;
typedef void (*BoazHostCacheCompletion)(void* context, BoazHostProfile profile,
    uint64_t request, BoazHostCacheStatus status);

typedef enum BoazHostAutomationState { BOAZ_AUTOMATION_DISABLED, BOAZ_AUTOMATION_STARTING,
  BOAZ_AUTOMATION_READY, BOAZ_AUTOMATION_FAILED } BoazHostAutomationState;
typedef void (*BoazHostAutomationVisitor)(void* context, BoazHostAutomationState state,
    uint8_t requested_at_startup, uint16_t port, const char* error);

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
  uint8_t audible;
  uint8_t muted;
  int32_t find_match_count;
  int32_t find_active_match;
  uint8_t find_final;
  int32_t load_error;
  const char* failed_url;
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

typedef enum BoazHostDownloadState {
  BOAZ_DOWNLOAD_PROGRESS, BOAZ_DOWNLOAD_COMPLETE, BOAZ_DOWNLOAD_CANCELLED, BOAZ_DOWNLOAD_INTERRUPTED
} BoazHostDownloadState;
typedef enum BoazHostDownloadAction {
  BOAZ_DOWNLOAD_PAUSE, BOAZ_DOWNLOAD_RESUME, BOAZ_DOWNLOAD_CANCEL
} BoazHostDownloadAction;
typedef struct BoazHostDownload {
  uint64_t id;
  const char* filename;
  int64_t received, total;
  BoazHostDownloadState state;
  int32_t interrupt_reason, danger_type;
  uint8_t paused, can_resume, dangerous, removed;
} BoazHostDownload;
/* Borrowed snapshot; copy before returning. Never reenter the host. */
typedef void (*BoazHostDownloadVisitor)(void* context, BoazHostProfile profile,
    const BoazHostDownload* download);

typedef enum BoazHostKeySystem { BOAZ_KEY_WIDEVINE, BOAZ_KEY_PLAYREADY } BoazHostKeySystem;
typedef struct BoazHostCallbacks {
  size_t size;
  void* context;
  void (*page_event)(void* context, BoazHostPageEvent event,
                     const BoazHostPageState* state);
  BoazHostResult (*prepare_window)(void* context, BoazHostProfile profile, BoazHostWindowRole role, BoazHostWindowOptions* options);
  void (*window_created)(void* context, BoazHostWindow window,
                         void* window_context);
  void (*window_closed)(void* context, BoazHostWindow window);
  void (*shutdown_ready)(void* context);
  /* Borrowed ordered URL batch, copied before callback returns. */
  void (*external_urls)(void* context, const char* const* urls, size_t count);
  BoazHostDownloadVisitor download_changed;
  /* Untrusted intent; identities are derived from the current primary document. */
  void (*protected_media)(void* context, BoazHostPage page, uint64_t navigation,
      BoazHostProfile profile, BoazHostKeySystem key_system);
  /* Browser-validated focused document; receiver owns nonzero token and releases
   * it after leaving this callback. Zero document dismisses the prior offer.
   * Origin is borrowed; screen bounds are presentation data, never authority. */
  void (*password_focus)(void* context, BoazHostPage page, uint64_t sequence,
      BoazHostDocument document, const char* origin,
      double screen_x, double screen_y, double width, double height);
  /* Per-window docking: 0 right, 1 bottom, 2 left, 3 undocked.
   * Last dock side excludes undocked. UI notification; no API reentry. */
  void (*devtools_dock_changed)(void* context, BoazHostWindow window,
      int32_t current, int32_t last);
  /* Browser-validated successful submission. Own/release document token after
   * callback; strings are borrowed. Credentials must never be logged. */
  void (*password_submission)(void* context, BoazHostPage page, BoazHostDocument document,
      const char* source_origin, const char* document_origin,
      const char* username, size_t username_length, const char* password, size_t password_length);
  void (*extensions_changed)(void* context, BoazHostWindow window);
} BoazHostCallbacks;

/* Enumeration values are borrowed for the visitor call. Visitors must copy
 * strings and must not reenter the API. Only enabled profile actions appear. */
typedef void (*BoazHostExtensionVisitor)(void* context, const char* extension_id,
                                        const char* name);

typedef void (*BoazHostHistoryVisitor)(void* context, int32_t entry_id,
    int32_t offset, const char* url, const char* title);

/* All calls and callbacks use Chromium's UI thread, also the AppKit main thread.
 * Handles are never reused during a process. Callbacks must not reenter the API.
 * PAGE_CLOSING and PAGE_VIEW_WILL_CHANGE are synchronous and permit only
 * native-view detachment. Other events wait until model mutation unwinds. */
/* Borrowed installed-extension metadata; copy before returning, no API reentry. */
typedef void (*BoazHostManagedExtensionVisitor)(void* context, const char* id,
    const char* name, const char* version, uint8_t enabled, uint8_t can_disable, uint8_t can_enable, uint8_t can_uninstall, uint8_t needs_permission_review);

typedef enum BoazHostExtensionInstallResult {
  BOAZ_EXTENSION_INSTALLED, BOAZ_EXTENSION_INSTALL_CANCELLED, BOAZ_EXTENSION_INSTALL_FAILED
} BoazHostExtensionInstallResult;
typedef void (*BoazHostExtensionInstallCompletion)(void* context, BoazHostWindow window,
    uint64_t request, BoazHostExtensionInstallResult result);

typedef void (*BoazHostExtensionMetadataVisitor)(void* context, const char* title, const char* badge,
    const uint8_t* png, size_t png_size);

/* Saved top-level site permissions: kind camera/microphone/notifications (0..2),
 * setting ask/allow/block/other (0..3). Origin is borrowed during visitor. */
typedef void (*BoazHostSitePermissionVisitor)(void* context, const char* origin,
    int32_t kind, int32_t setting, uint8_t can_reset, uint8_t embargoed);

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
  /* Accepted requests complete once asynchronously before shutdown_ready. */
  BoazHostResult (*prepare_profile)(const char* identifier, uint8_t is_private,
      BoazHostProfileCompletion completion, void* context);
  BoazHostResult (*create_profile_window)(BoazHostProfile profile,
      const BoazHostWindowOptions* options, BoazHostWindow* window);
  BoazHostResult (*release_profile)(BoazHostProfile profile);
  BoazHostResult (*set_audio_muted)(BoazHostPage page, uint8_t muted);
  BoazHostResult (*get_zoom_factor)(BoazHostPage page, double* factor);
  BoazHostResult (*set_zoom_factor)(BoazHostPage page, double factor);
  BoazHostResult (*find_text)(BoazHostPage page, const char* text, uint8_t forward);
  BoazHostResult (*stop_find)(BoazHostPage page);
  BoazHostResult (*stop_loading)(BoazHostPage page);
  BoazHostResult (*enumerate_history)(BoazHostPage page, BoazHostHistoryVisitor visitor, void* context);
  BoazHostResult (*go_to_history_entry)(BoazHostPage page, int32_t entry_id);
  BoazHostResult (*is_busy_for_residency)(BoazHostPage page, uint8_t* busy);
  BoazHostResult (*show_devtools)(BoazHostPage page, BoazHostDevToolsAction action);
  /* Captures one validated document and its browser-authoritative origin atomically.
   * Supply a 2048-byte origin buffer. Failure clears outputs and retains no token.
   * Success uses the same single-use execution/release contract as capture_document. */
  BoazHostResult (*capture_document_origin)(BoazHostPage page, BoazHostDocument* document,
                                          char* origin, size_t capacity);
  /* Request must be nonzero; max dimensions <=2048, area <=2097152 pixels.
   * Captures only visible surfaces. Synchronous rejection produces no callback. */
  BoazHostResult (*capture_visible)(BoazHostPage page, uint64_t request,
      int32_t width, int32_t height, BoazHostCaptureCompletion completion, void* context);
  BoazHostResult (*cancel_capture)(BoazHostPage page, uint64_t request);
  /* A null viewport clears native overrides. Accepted operations complete once on UI. */
  BoazHostResult (*apply_viewport)(BoazHostPage page, const BoazHostViewport* viewport,
      uint64_t request, BoazHostEmulationCompletion completion, void* context);
  BoazHostResult (*get_user_agent_defaults)(BoazHostPage page, BoazHostUserAgentVisitor visitor, void* context);
  /* Null user_agent resets defaults. Custom values suppress Client Hints. */
  BoazHostResult (*apply_user_agent)(BoazHostPage page, const char* user_agent, size_t length,
      uint64_t request, BoazHostEmulationCompletion completion, void* context);
  BoazHostResult (*enumerate_downloads)(BoazHostProfile profile, BoazHostDownloadVisitor visitor, void* context);
  /* Actions require explicit user activation; no dangerous-download override. */
  BoazHostResult (*download_action)(BoazHostProfile profile, uint64_t download, BoazHostDownloadAction action);
  /* Opens the native print dialog; OK means accepted, not printed. */
  BoazHostResult (*print_page)(BoazHostPage page);
  /* Update before closing the last Chromium page. Does not close a window. */
  BoazHostResult (*set_external_tab_count)(BoazHostWindow window, uint32_t count);
  /* PDF bytes use capture status, max 32 MiB, 30-second deadline. Cancellation
   * stops delivery; Chromium may finish the underlying print job afterward. */
  BoazHostResult (*capture_pdf)(BoazHostPage page, uint64_t request,
      BoazHostCaptureCompletion completion, void* context);
  BoazHostResult (*cancel_pdf)(BoazHostPage page, uint64_t request);
  /* Null media resets all media and vision overrides. */
  BoazHostResult (*apply_media)(BoazHostPage page, const BoazHostMedia* media,
      uint64_t request, BoazHostEmulationCompletion completion, void* context);
  /* Profile resource caches only; cookies and Cache Storage remain intact. */
  BoazHostResult (*clear_cache)(BoazHostProfile profile, uint64_t request,
      BoazHostCacheCompletion completion, void* context);
  BoazHostResult (*reload_from_origin)(BoazHostPage page);
  BoazHostResult (*apply_network)(BoazHostPage page, const BoazHostNetwork* network,
      uint64_t request, BoazHostEmulationCompletion completion, void* context);
  BoazHostResult (*apply_cpu)(BoazHostPage page, double rate,
      uint64_t request, BoazHostEmulationCompletion completion, void* context);
  BoazHostResult (*apply_sensors)(BoazHostPage page, const BoazHostSensors* sensors,
      uint64_t request, BoazHostEmulationCompletion completion, void* context);
  BoazHostResult (*set_javascript_disabled)(BoazHostPage page, uint8_t disabled);
  /* No credentials are exposed by this synchronous status visitor. */
  BoazHostResult (*automation_status)(BoazHostAutomationVisitor visitor, void* context);
  /* Full currently laid-out document, PNG, <=32 MiB and <=32 Mi pixels.
   * Accepted failure/timeout detaches emulation; BUSY rejection preserves it. */
  BoazHostResult (*capture_full_page)(BoazHostPage page, uint64_t request,
      BoazHostCaptureCompletion completion, void* context);
  BoazHostResult (*cancel_full_page)(BoazHostPage page, uint64_t request);
  /* Browser-selected focused frame; no caller-supplied frame identity. */
  BoazHostResult (*capture_focused_document_origin)(BoazHostPage page, BoazHostDocument* document,
      char* origin, size_t capacity);
  /* Independent single-use token for the exact same validated document. */
  BoazHostResult (*clone_document)(BoazHostPage page, BoazHostDocument document, BoazHostDocument* clone);
  BoazHostResult (*set_devtools_dock_preferences)(BoazHostWindow window,
      int32_t current, int32_t last);
  BoazHostResult (*enumerate_managed_extensions)(BoazHostProfile profile,
      BoazHostManagedExtensionVisitor visitor, void* context);
  BoazHostResult (*disable_extension)(BoazHostProfile profile, const char* id);
  BoazHostResult (*enable_extension)(BoazHostProfile profile, const char* id);
  BoazHostResult (*install_extension)(BoazHostWindow window, const char* path, uint64_t request,
      BoazHostExtensionInstallCompletion completion, void* context);
  BoazHostResult (*install_unpacked_extension)(BoazHostWindow window, const char* path, uint64_t request,
      BoazHostExtensionInstallCompletion completion, void* context);
  BoazHostResult (*uninstall_extension)(BoazHostProfile profile, const char* id);
  BoazHostResult (*extension_metadata)(BoazHostWindow window, BoazHostPage page,
      const char* id, BoazHostExtensionMetadataVisitor visitor, void* context);
  BoazHostResult (*review_extension_permissions)(BoazHostWindow window, const char* id, uint64_t request,
      BoazHostExtensionInstallCompletion completion, void* context);
  BoazHostResult (*toggle_picture_in_picture)(BoazHostPage page);
  BoazHostResult (*enumerate_site_permissions)(BoazHostPage page, uint64_t navigation,
      BoazHostSitePermissionVisitor visitor, void* context);
  BoazHostResult (*reset_site_permission)(BoazHostPage page, uint64_t navigation, int32_t kind);
} BoazHostAPI;

/* Called once by the prototype host after its isolated profile is ready.
 * The table remains valid through shutdown_ready. No production profile opens. */
typedef BoazHostResult (*BoazNativeUIStart)(const BoazHostAPI* api);

#ifdef __cplusplus
}
#endif

#endif
