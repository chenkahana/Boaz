# Boaz on the App Store

Everything needed to submit Boaz for iPhone and Mac. Facts here match the code as of version 1.0 (build 1).

## App record

| Field | Value |
|---|---|
| Name | Boaz Browser ("Boaz" is taken) |
| Bundle ID | `com.chenkahana.boaz` (iPhone and Mac share it: one record, universal purchase) |
| Platforms | iOS (iPhone; runs on iPad in compatibility mode) and macOS |
| SKU | `boaz` |
| Primary / secondary category | Productivity / Utilities |
| Minimum OS | iOS 27.1, macOS 26.0 |
| Version / build | 1.0 / 1 (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` in `project.yml`) |
| Price | Free |
| Support URL | https://github.com/chenkahana/Boaz/issues |
| Privacy Policy URL | https://github.com/chenkahana/Boaz/blob/master/docs/privacy.md |

## Listing text

**Subtitle** (30 max): `Calm browsing on iPhone & Mac`

**Promotional text** (170 max):
Opens right where you left off, follows every posture of iPhone Duo, and keeps your tabs in step with your Mac. No
ads, no trackers, no accounts.

**Description**:

Boaz is a calm, fast browser that keeps your web organized the way you think.

PICK UP WHERE YOU LEFT OFF
On iPhone, Boaz opens on the last page you had open. A bar at the bottom, within thumb reach, holds your recent tabs,
New Tab and the page menu. Tap the tabs to flip through all of them.

MADE FOR IPHONE DUO
Folded, the page fills the screen. Open it and a sidebar with search and your tabs sits next to the page. Half-open
like a laptop, the page stays on top and the controls move below. The page never reloads as the hinge moves.

SEARCH THAT KNOWS YOUR TABS
Suggestions from your search engine, mixed with your open tabs and history. Nothing is sent from Incognito.

SPACES ON THE MAC
Keep work, home and projects apart. Each space has its own color, pinned tabs and favorites.

TABS THAT TIDY THEMSELVES
New tabs land in Today. Ones you haven't opened in a while move to the Archive on their own, so the clutter never
builds up. Pin what matters and it stays.

IN STEP ON IPHONE AND MAC
Pins, favorites and tabs sync through your private iCloud. Each device keeps its own Today list, and your iPhone
can open the tabs on your Mac.

ON-DEVICE INTELLIGENCE
Summarize a page, ask it questions, or sort your tabs into folders, using Apple's on-device model on supported
devices. Nothing leaves your device.

BRING ARC WITH YOU
On Mac, import your Arc spaces, pinned folders, favorites, themes and keyboard shortcuts as they are. Chrome, Brave,
Edge and Safari bookmarks come in too.

PRIVATE BY DESIGN
Ads and trackers are blocked. On iPhone, cookie banners can be declined for you. Incognito tabs leave nothing behind. No
accounts, no analytics, no data collected.

Arc is a trademark of The Browser Company. Boaz is not affiliated with or endorsed by The Browser Company.

**Keywords** (100 max): `browser,tabs,spaces,sidebar,web,private,ad blocker,sync,bookmarks,foldable,incognito` (no "arc": Guideline 2.3.7 bars other apps' trademarks in keywords)

## App Privacy (questionnaire)

Answer **"No, we do not collect data from this app."** Rationale: no analytics or third-party SDKs; the library
syncs through the user's private CloudKit database, which Apple does not treat as developer collection; history
stays on device. The bundled privacy manifest (`Apps/Shared/PrivacyInfo.xcprivacy`) declares no tracking and no
collected data, plus required-reason APIs (UserDefaults CA92.1/1C8F.1, file timestamps C617.1/3B52.1).

## Age rating

Answer **Unrestricted Web Access: Yes** (it's a browser); everything else None. App Store Connect then rates it 18+.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is in both Info.plists, so builds skip the encryption question (HTTPS through
the system only).

## Notes for App Review (paste into "Notes")

No account or sign-in is needed, and iCloud sync is optional during the short first-run setup.

- iPhone: tap **+** (New Tab) in the bar at the bottom to search or enter an address. The fan of tabs at its left
  opens the tab carousel: tap a card to open that tab, swipe it up to archive it; the gear button there opens Settings. **…**
  opens the page menu (Back, Forward, Reload, Share, Pin, Reader and more). On iPhone Duo the layout follows the
  hinge (folded, the controls move to a rail beside the page; a sidebar next to the page when open; page above
  controls when half-open).
- Mac: links from other apps open in a small Quick Window; "Open in Boaz" moves them into the main window.
- Import from Arc (Mac, optional) needs Arc installed: File › Import from Arc… asks you to choose Arc's data folder
  (~/Library/Application Support/Arc). "Keep me signed in" (copy Arc's cookies) is a separate, opt-in checkbox; macOS then asks
  permission to read Arc's "Arc Safe Storage" key, used only to decrypt Arc's cookie file on this Mac. Cookies are
  never uploaded or synced. Saved passwords are not imported.
- iCloud is optional; without it Boaz works fully on one device.
- Camera, microphone and location prompts appear only when a website asks for them.

## Screenshots

Generated into `docs/screenshots/` (not part of the app build).

| Display | Required size | Files |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 portrait | `iphone-69-*.png` |
| Mac | 1440 × 900 | `mac-*.png` |

The iOS 27.1 simulator only offers iPhone Duo, whose screens aren't an App Store size, so each `iphone-69-*` image is
a Duo screenshot (`duo-*.png`, folded, and the unfolded inner screen) captioned on the brand gradient. The Mac images
are the app window on the same gradient.

iPad screenshots aren't needed for an iPhone-only app.

## Owner checklist (in order)

1. **CloudKit Console** (icloud.developer.apple.com) › container `iCloud.com.chenkahana.boaz` › *Deploy Schema
   Changes* to Production. Without this, App Store builds can't sync (they use the production environment).
2. **App Store Connect** › Apps › New App: iOS and macOS, name Boaz Browser, bundle ID `com.chenkahana.boaz`, SKU `boaz`.
3. **Upload builds**: double-click `build/archives/Boaz-iOS.xcarchive` and `Boaz-macOS.xcarchive` (opens them in
   Xcode's Organizer) › Distribute App › App Store Connect › Upload. To rebuild them first, run `make archive`.
   Raise `CURRENT_PROJECT_VERSION` in `project.yml` for every new upload, and add the release to `CHANGELOG.md`.
4. Fill the listing from this file, upload the screenshots, answer App Privacy and Age Rating as above.
5. Add both builds to version 1.0 and **Submit for Review**.

## Xcode Cloud

`ci_scripts/` makes the repo buildable on Xcode Cloud, which only sees what's checked in:

- `ci_post_clone.sh` installs the pinned XcodeGen (same release and SHA-256 as GitHub CI), sets
  `CURRENT_PROJECT_VERSION` to Xcode Cloud's build number, generates `Boaz.xcodeproj`, and copies
  `Packages/BoazKit/Package.resolved` into it (Xcode Cloud never resolves packages on its own).
- `ci_post_xcodebuild.sh` fills TestFlight's "What to Test" with the last five commit subjects after an App Store archive.

The `Boaz-iOS` and `Boaz-macOS` schemes are shared (`scheme: {}` in `project.yml`), which Xcode Cloud requires.
Create the workflows once in Xcode (Product › Xcode Cloud › Create Workflow): Archive `Boaz-iOS` and `Boaz-macOS`
on pushes to `master`, with TestFlight (Internal Testing) as the post-action, on the newest Xcode 27 environment.
