# Roadmap

Boaz's direction: the go-to browser for people who value **simplicity, stability and accuracy**.

This page is the public highlights, in the order we work them. Releases and their contents are always in
[CHANGELOG.md](CHANGELOG.md). The working-level plan board is kept privately; what ships is always public.

## Now: stability

- Green, trustworthy CI, including the Mac UI tests
- Runtime acceptance of the Chromium build: upgrades, profiles, passwords, downloads and extensions, proven on
  real installs rather than plausible from source
- A drilled Chromium security-update runbook: an upstream patch to a published, notarized release inside 72 hours
- Refreshed performance baselines, so slowdowns become bugs instead of surprises

## Next: accuracy

- Phishing and malware protection, without your browsing history leaving the device
- Passwords that sync across your iPhone and Mac, with AutoFill on iOS
- One clear, honest story for the two builds: the App Store apps run WebKit, the Mac DMG from GitHub runs Chromium

## Later: simplicity

- Site-to-space routing: work links open in your Work space automatically, wherever you click them
- Tab groups in the sidebar
- Per-site customization, the lite way: your own CSS per site, with a few one-tap presets

## Operations

- A TestFlight beta ring
- Crash reporting that respects you: no telemetry, ever
- A routine App Store submission pipeline

## Not planned

- **History sync and server-side AI**: privacy choices, not gaps. See [docs/privacy.md](docs/privacy.md).
- **Windows and Android**: Boaz is Apple-native on purpose.
- **Widevine DRM and passkeys**: waiting on Google and Apple, not on engineering.

Something you'd like to see? [Open an issue](https://github.com/chenkahana/Boaz/issues/new?template=feature_request.yml).
