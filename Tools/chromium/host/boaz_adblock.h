#ifndef BOAZ_ADBLOCK_H
#define BOAZ_ADBLOCK_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct BoazAdblockSnapshot BoazAdblockSnapshot;
typedef struct { const uint8_t* data; size_t len; } BoazAdblockBytes;
typedef struct { uint8_t* data; size_t len; } BoazAdblockBuffer;
enum { BOAZ_ADBLOCK_OK = 0, BOAZ_ADBLOCK_INVALID = 1,
       BOAZ_ADBLOCK_TOO_LARGE = 2, BOAZ_ADBLOCK_PANIC = 3,
       BOAZ_ADBLOCK_REJECTED_INPUT = 4 };

/* All pointers must be valid/aligned for their declared lengths; outputs must not alias inputs. */
/* Snapshots permit concurrent queries; caller excludes destruction until all queries finish. */
/* Every returned buffer, including diagnostics on failure, requires exactly one buffer_free. */
/* Rules: standard ABP UTF-8 <=64MiB. Resources: upstream Resource JSON array <=64MiB. */
/* Creation rejects unsupported rules/resources; diagnostics include counts + first 32 indices. */
/* Blank lines, !/#-space comments and [Adblock headers are not rejected rules. */
int32_t boaz_adblock_create(BoazAdblockBytes rules, BoazAdblockBytes resources,
                           BoazAdblockSnapshot** out, BoazAdblockBuffer* diagnostics);
/* URL/source <=64KiB; kind <=64B, method <=32B. JSON includes should_block and full result. */
/* Caller must honor exceptions, important, redirect and rewritten_url with upstream semantics. */
int32_t boaz_adblock_network(const BoazAdblockSnapshot*, BoazAdblockBytes url,
                            BoazAdblockBytes source, BoazAdblockBytes kind,
                            BoazAdblockBytes method, BoazAdblockBuffer*);
/* Full UrlSpecificResources JSON: selectors, procedural actions, exceptions, script, generichide. */
int32_t boaz_adblock_cosmetics(const BoazAdblockSnapshot*, BoazAdblockBytes url,
                              BoazAdblockBuffer*);
/* <=64KiB JSON object: classes, ids, exceptions string arrays. Skip when generichide is true. */
int32_t boaz_adblock_selectors(const BoazAdblockSnapshot*, BoazAdblockBytes input,
                              BoazAdblockBuffer*);
/* Cache is version-specific, excludes resource assets; restore is deliberately not exposed yet. */
int32_t boaz_adblock_serialize(const BoazAdblockSnapshot*, BoazAdblockBuffer*);
/* Outputs capped at128MiB after computation; this is not an allocator peak-memory guarantee. */
/* Panic conversion requires unwind; allocation failure/invalid caller pointers are not recoverable. */
void boaz_adblock_buffer_free(BoazAdblockBuffer);
void boaz_adblock_destroy(BoazAdblockSnapshot*);
#ifdef __cplusplus
}
#endif
#endif
