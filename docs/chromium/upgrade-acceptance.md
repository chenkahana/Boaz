# Upgrade and runtime acceptance: the manual part

Must-have #13 says an upgrade never loses the library: spaces, tabs, folders, history, passwords and sign-ins. The
[Upgrade acceptance workflow](../../.github/workflows/upgrade-acceptance.yml) checks most of it on a throwaway Mac
in CI (`Tools/acceptance/upgrade.sh`). It installs a published DMG, seeds a library, settings and a cookie sign-in,
upgrades to a newer published DMG and compares. The [Runtime acceptance workflow](../../.github/workflows/runtime-acceptance.yml)
(`Tools/acceptance/runtime.py`) drives a published DMG through its own Local Automation. Neither can check what
needs a person, a real account or a macOS permission prompt. That's this script: about 25 minutes for the upgrade
part, then about 30 for the runtime part, under an hour in all.

## What CI already covers

Every space, tab, folder, archive item, history visit and profile row survives, unchanged. The library stays in the
old container and no second one appears. Settings come across. The old website data is never touched. A cookie
sign-in on a local test site survives the upgrade and the next launch. A failure there blocks the release.

## What this script covers

1. A real, long-lived library, not a fixture.
2. Real sign-ins: Google, Apple, Microsoft, GitHub, including sites with two-factor sessions.
3. Saved passwords.
4. The in-app update (Sparkle) instead of replacing the app by hand.
5. Gatekeeper's first-open dialog for a downloaded DMG.
6. The Keychain prompt for "Boaz Chromium Safe Storage", if macOS shows one.
7. iCloud sync after the upgrade.
8. A second profile's sign-ins.

## Before you start

Use a spare macOS user account if you can. On your own account, back up first, with Boaz quit:

```sh
mkdir -p ~/BoazBackup
ditto ~/Library/Containers/com.chenkahana.boaz ~/BoazBackup/Container
ditto "$HOME/Library/Application Support/Boaz" ~/BoazBackup/ApplicationSupport 2>/dev/null
cp ~/Library/Preferences/com.chenkahana.boaz.plist ~/BoazBackup/ 2>/dev/null
```

To restore, quit Boaz and copy these three back.

You need the version you're upgrading from (for the sandboxed library, [v0.2.18](https://github.com/chenkahana/Boaz/releases/tag/v0.2.18))
and the one you're upgrading to.

## Steps

1. **Install the old version.** Download its `Boaz.dmg` in Safari, open it and drag Boaz to Applications. Open it,
   and note the version in Boaz ▸ About Boaz.
2. **Use it as you normally would.** Sign in to Google, Apple ID (appleid.apple.com), Microsoft (outlook.com) and
   GitHub, with two-factor where you have it. Save one password per site when Boaz offers. Make a second space with a
   pinned folder and a Today tab. Archive a tab. Change a setting, such as the search engine. If you use a second
   profile, sign in to one site there too. Write down what you did in the results table.
3. **Quit Boaz** with Boaz ▸ Quit Boaz.
4. **Upgrade with the in-app update.** Open Boaz, choose Boaz ▸ Check for Updates and install the newer version.
   When that version isn't published yet, download its DMG in Safari and drag it over the old app instead. Then
   Gatekeeper shows its first-open dialog: note its wording and click Open.
5. **Watch the first launch.** Note any dialog macOS shows: a Keychain prompt for "Boaz Chromium Safe Storage", or
   one about data from other apps. Click Allow (or Always Allow) and write down which.
6. **Check everything is there.** All spaces with their pinned tabs, folders and Today tabs. The archive and
   history. The setting you changed. Open each site from step 2: you should still be signed in, with no new
   two-factor prompt. Open Passwords: each saved password is listed and fills on its site.
7. **Second profile.** Switch to a space in the second profile and open the site you signed in to there.
8. **iCloud.** On the iPhone, check that a Today tab you open on the Mac after the upgrade arrives.
9. **Quit and open Boaz again.** Repeat the checks in step 6 quickly. Sign-ins must survive a second launch.
10. **If anything is missing,** don't use Boaz further. Quit it and keep the evidence: Console logs for
    `com.chenkahana.boaz`, and a copy of the three folders from "Before you start". File an issue
    ([docs/qa.md](../qa.md#reporting)), severity P1.

## Runtime

Do this right after the upgrade, in the same Boaz. Each step names its row in [parity.md](parity.md), so a result
can go straight there.

1. **Sign-in popups (B2).** On a site with "Sign in with Google", with Apple and with Microsoft (for example
   figma.com, or any site you use), sign in through the popup. The popup closes by itself and the page is signed in.
2. **Location (P1).** Open maps.google.com and click "Your location". Boaz asks first, then macOS asks once. Allow
   both: the map moves to you. Quit and reopen Boaz: it doesn't ask again. Remove the permission in Settings, then
   reload: Boaz asks again.
3. **Notifications (P1).** On a site that offers notifications (for example web.whatsapp.com, or any site you use),
   allow them. Boaz asks first, then macOS asks once. A notification arrives in Notification Center, named Boaz.
4. **Camera and microphone (P1).** Open meet.google.com/landing and start a meeting preview. Boaz asks for the camera
   and microphone; allow both and you see yourself. In a space of your other profile, the same site asks again.
5. **Password managers (E1/E2).** Install 1Password and Bitwarden from the Chrome Web Store. Unlock each with your
   own account and fill a login with it. Uninstall the one you don't use.
6. **Protected video (#1, M4).** Play a minute of something on Netflix or Disney+. It plays. No menu, setting,
   badge or window mentions WebKit, Safari or an engine, before, during or after playback.
7. **Passwords sync (P3).** On a site, save a password when Boaz offers. On the iPhone, it shows in Boaz's
   passwords after sync, and it fills on the Mac.
8. **Default browser (U1).** Make Boaz the default browser in System Settings ▸ Desktop & Dock. A link clicked in
   Mail or Messages opens in Boaz.
9. **iPhone (R1).** In Boaz on the iPhone: scroll a long page, fill a saved password, play a video in Picture in
   Picture, sign in through a popup, and check an ad-heavy page shows no ads.

## Results

Copy this table into the PLAN-02 progress log, or into the issue for a failure.

| Field | Result |
|---|---|
| Date | |
| From version → to version | |
| Mac, macOS version | |
| How it upgraded (in-app update / DMG replace) | |
| Gatekeeper dialog (wording) | |
| Keychain or other macOS prompts, and the button clicked | |
| Spaces, pinned tabs, folders, Today tabs | pass / fail |
| Archive and history | pass / fail |
| Settings | pass / fail |
| Google sign-in | pass / fail |
| Apple sign-in | pass / fail |
| Microsoft sign-in | pass / fail |
| GitHub sign-in | pass / fail |
| Saved passwords listed and filled | pass / fail |
| Second profile sign-in | pass / fail / not used |
| iCloud sync after the upgrade | pass / fail / not used |
| Still signed in after a second launch | pass / fail |
| B2 Sign-in popups: Google, Apple, Microsoft | pass / fail |
| P1 Location: Boaz then macOS ask, remembered, revoked | pass / fail |
| P1 Notifications: asked, delivered as Boaz | pass / fail |
| P1 Camera and microphone, per profile | pass / fail |
| E1/E2 1Password and Bitwarden unlock and fill | pass / fail / not used |
| #1/M4 Netflix or Disney+ plays, no engine shown anywhere | pass / fail |
| P3 Password saved, synced to iPhone, filled | pass / fail |
| U1 Default browser after the upgrade | pass / fail |
| R1 iPhone smoke: scroll, password, PiP, popup, blocking | pass / fail |
| Notes, evidence paths | |
