# Development signing for the CEF spike

After the spike finishes building, stage a separately signed copy. Select the exact Apple Development certificate SHA1 from the available signing identities. Keep that certificate and the bundle identifiers stable across rebuilds.

```sh
python3 Tools/cef/sign-spike.py \
  --app /absolute/build/BoazCEFSpike.app \
  --output /absolute/staging/BoazCEFSpike.app \
  --identity CERTIFICATE_SHA1
```

The output parent must exist. The tool refuses an existing output or report, verifies the input bundle identifier, preserves symlinks, and copies the app before signing. It omits only `Contents/MacOS/BoazCEFSpike.d`, a build dependency file that prevents bundle signing. Broken or escaping symlinks fail validation. All five helpers and the framework are required.

The tool inventories actual framework Mach-O files and signs them before the framework, helper bundles, and outer application. Only GPU and Renderer helpers receive `allow-jit`. Signing uses no `--deep`; final verification uses `--deep --strict`. The adjacent `.app.signing.json` records commands, component inventory, verification output, and failures. Failed staging output remains available for inspection. The original app stays untouched.

This uses the component order and options from pinned Chromium [parts.py](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/installer/mac/signing/parts.py), its [development signing guidance](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/installer/mac/signing/README.md), and the exact [Renderer](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/app/helper-renderer-entitlements.plist) and [GPU](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/app/helper-gpu-entitlements.plist) entitlements. CEF's process sandbox initialization remains unchanged. No App Sandbox entitlement is added.

Apple Development signing validates local operation. It does not establish Developer ID distribution or notarization. No runtime success is inferred from signature verification. The Plugin helper starts without extra entitlement exceptions; its behavior still needs runtime acceptance.

[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) describes Keychain access tracking through designated requirements. Stable signing is a diagnostic for access failures after rebuilding, not proof of the shutdown failure's cause. Signing may prompt for private-key access; an existing Chromium Keychain item may separately require Chen's authorization. The tool does not read secrets, alter access controls, or reset Keychain data.

Verification for this tooling commit is limited to Python syntax and CLI help. The orchestrator runs actual signing on the rebuilt spike, then compares designated requirements across one rebuild and repeats the shutdown scenario. Signing must happen after every build or bundle change.
