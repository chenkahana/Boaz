#ifndef BOAZ_CHROMIUM_PROTECTED_MEDIA_H_
#define BOAZ_CHROMIUM_PROTECTED_MEDIA_H_
#include "boaz/protected_media.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
namespace content { class RenderFrameHost; }
namespace boaz {
void BindProtectedMediaObserver(content::RenderFrameHost* frame,
    mojo::PendingReceiver<mojom::EncryptedMediaObserver> receiver);
}
#endif
