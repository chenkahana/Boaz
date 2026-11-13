# Development signing for the CEF spike

After the spike finishes building, stage a separately signed copy. Select the exact Apple Development certificate SHA1 from the available signing identities. Keep that certificate and the bundle identifiers stable across rebuilds.

```sh
python3 Tools/cef/sign-spike.py \
  --app /absolute/build/BoazCEFSpike.app \
  --output /absolute/staging/BoazCEFSpike.app \
  --identity CERTIFICATE_SHA1
```

The output parent must exist. The tool refuses an existing output or report, verifies the input bundle identifier, preserves symlinks, and copies the app before signing. It omits only `Contents/MacOS/BoazCEFSpike.d`, a build dependency file that prevents bundle signing. Broken or escaping symlinks fail validation. All five helpers and the framework are required.

The tool normalizes staged Info.plist files with `plutil -convert xml1`, then inventories actual framework Mach-O files and signs them before the framework, helper bundles, and outer application. Only GPU and Renderer helpers receive `allow-jit`. Signing uses no `--deep`; final verification uses `--deep --strict`. The adjacent `.app.signing.json` records commands, component inventory, verification output, and failures. Failed staging output remains available for inspection. The original app stays untouched.

This uses the component order and options from pinned Chromium [parts.py](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/installer/mac/signing/parts.py), its [development signing guidance](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/installer/mac/signing/README.md), and the exact [Renderer](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/app/helper-renderer-entitlements.plist) and [GPU](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/app/helper-gpu-entitlements.plist) entitlements. CEF's process sandbox initialization remains unchanged. No App Sandbox entitlement is added.

Apple Development signing validates local operation. It does not establish Developer ID distribution or notarization. No runtime success is inferred from signature verification. The Plugin helper starts without extra entitlement exceptions; its behavior still needs runtime acceptance.

[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) describes Keychain access tracking through designated requirements. Stable signing is a diagnostic for access failures after rebuilding, not proof of the shutdown failure's cause. Signing may prompt for private-key access; an existing Chromium Keychain item may separately require Chen's authorization. The tool does not read secrets, alter access controls, or reset Keychain data.

## Runtime evidence, 2026-11-13

Actual staging and Apple Development signing passed nested strict verification. The app's designated requirement now uses its identifier and Apple certificate chain rather than an ad-hoc code hash. This does not establish runtime success or Developer ID distribution.

Two packaging failures were resolved before verification passed. The Swift build emits a dependency file into `Contents/MacOS`, which staging now excludes. The upstream `COPY_MAC_FRAMEWORK` macro uses `ln -sf`, which follows existing directory symlinks on incremental builds and creates broken nested links. The spike now uses `ln -sfn`; rebuilt and repeated link operations produced four valid links and no broken links. The original malformed build framework was preserved for inspection.

The first signed run reported runtime error `-67030`, invalid Info.plist, despite valid signatures on disk. Pinned Chromium [info_plist_data.mm](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/base/mac/info_plist_data.mm) serializes the bundle dictionary as XML for [dynamic signature validation](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/base/mac/code_signature.cc). Its bytes differed from the compact template. Normalizing before signing removed that error in the next run. The existing ad-hoc-created profile still stalled; signing alone has not resolved lifecycle acceptance. No Keychain item or access policy was changed.

Signing must happen after every build or bundle change. Stable identity across a rebuild, reliable shutdown, notarization, and clean-account launch remain acceptance requirements.

A rebuilt and re-signed binary retained the same designated requirement. With `BOAZ_CEF_SPIKE_PROFILE=signed-v1`, a fresh cache and Keychain namespace created by that signed app loaded HTTPS, exercised the extension, and exited 0. A second launch of the same signed binary/profile again loaded HTTPS and exited 0. No old profile, Keychain item, or access rule was removed or changed. This narrows the earlier failure to the old identity/profile path; it does not establish safe migration from an ad-hoc-created profile or broad lifecycle acceptance. The first extension-action run also logged a CEF browser-info timeout for a frame; that remains an unresolved extension lifecycle observation.
