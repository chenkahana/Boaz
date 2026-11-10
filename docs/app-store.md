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

**Subtitle** (30 max): `Spaces, pins and tabs, synced`

**Promotional text** (170 max):
Your spaces, pinned tabs and favorites, in step on iPhone and Mac. Bring your Arc sidebar over as is, and browse
without ads or trackers.

**Description**:

Boaz is a calm, fast browser that keeps your web organized the way you think.

SPACES FOR EVERYTHING
Keep work, home and projects apart. Each space has its own color, pinned tabs and favorites, and swiping moves
between them.

TABS THAT TIDY THEMSELVES
New tabs land in Today. Ones you haven't opened in a while move to the Archive on their own, so the clutter never
builds up. Pin what matters and it stays.

MADE FOR IPHONE AND MAC
Your spaces, pins and tabs stay in step through your private iCloud. On iPhone Duo, Boaz uses every posture:
sidebar and page side by side when open, the page above and controls below when half-open like a laptop.

BRING ARC WITH YOU
On Mac, import your Arc spaces, pinned folders, favorites, themes and keyboard shortcuts as they are. Chrome, Brave,
Edge and Safari bookmarks come in too.

PRIVATE BY DESIGN
Ads and trackers are blocked. On iPhone, cookie banners can be declined for you. Incognito tabs leave nothing behind. No
accounts, no analytics, no data collected.

**Keywords** (100 max): `browser,arc,tabs,spaces,sidebar,web,private,ad blocker,sync,bookmarks,foldable,incognito`

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

No account or sign-in is needed; the app opens with a starter library.

- iPhone: tap the search button to open a page; long-press a tab card to pin or close it; Settings is in the ≡
  menu on the home screen. On iPhone Duo the layout follows the hinge (side by side when open, page above controls when half-open).
  On other iPhones and on iPad the toolbar sits at the bottom.
- Mac: links from other apps open in a small "Little Boaz" window; "Open in Boaz" moves them into the main window.
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
