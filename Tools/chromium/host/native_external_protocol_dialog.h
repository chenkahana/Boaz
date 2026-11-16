#ifndef BOAZ_NATIVE_EXTERNAL_PROTOCOL_DIALOG_H_
#define BOAZ_NATIVE_EXTERNAL_PROTOCOL_DIALOG_H_
#include <optional>
#include <string>
#include "content/public/browser/weak_document_ptr.h"
#include "url/origin.h"
class GURL;
namespace content { class WebContents; }
namespace boaz {
// Chrome's "Open <app>?" confirmation, as a sheet on the tab's Boaz window.
void ShowNativeExternalProtocolDialog(content::WebContents*, const GURL&,
                                      const std::u16string& program_name,
                                      const std::optional<url::Origin>& initiating_origin,
                                      content::WeakDocumentPtr initiator_document);
}
#endif
