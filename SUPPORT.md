# Getting help

- **Something isn't working:** on Mac choose Help › Report a Problem…, or on iPhone open Settings › Report a
  Problem. A bug report opens with your Boaz version, build, device and OS filled in. You can also open a
  [bug report](https://github.com/chenkahana/Boaz/issues/new?template=bug_report.yml) yourself.
- **An idea or request:** open a [feature request](https://github.com/chenkahana/Boaz/issues/new?template=feature_request.yml).
- **A security problem:** don't post it publicly; see [SECURITY.md](SECURITY.md).
- **Privacy questions:** read the [privacy policy](docs/privacy.md).

## Sending a crash report

Boaz never sends crash reports on its own. If Boaz quit unexpectedly, you can add the report to your bug report:

- **Mac:** open Console (Applications › Utilities), choose Crash Reports, and select the newest report for Boaz. The
  version downloaded from GitHub files its reports as "Chromium", the engine it's built on. Control-click the report, choose Reveal in Finder, then Control-click the file and choose
  Compress. Drag the .zip into the bug report. GitHub doesn't accept .ips files as they are.
- **iPhone:** in the Settings app, open Privacy & Security › Analytics & Improvements › Analytics Data. Tap the
  newest entry that starts with "Boaz", tap Share and choose Save to Files. In Files, touch and hold the file,
  choose Compress, then attach the .zip to the bug report.

A crash report lists your device model, OS version and where in Boaz's code the crash happened. On a Mac it can
show your user name in file paths. Bug reports are public, so look it over before you attach it. If you share
analytics with app developers (Privacy & Security › Analytics & Improvements), Apple already passes crashes from
App Store and TestFlight builds to the developer without your name.

When only a web page crashes and Boaz keeps running, there's no crash report to send. Describe the page and what
you did instead.

### For maintainers: reading a report

`Tools/symbolicate REPORT.ips DSYMS…` prints the crashed thread with Boaz's function names, files and lines. It
reads the JSON `.ips` format (macOS 12 and later, iOS 15 and later). Pass the dSYMs of the exact build the report
names, either as a `.dSYM` or as a folder that holds them. For the DMG, use the `Boaz-X.Y.Z-dSYMs.zip` attached
to that GitHub release. For App Store builds, use the archive's `dSYMs` folder. dSYMs that Spotlight has indexed,
such as Xcode's DerivedData and archives, are found without being passed. Frames in Chromium's engine show only
what macOS recorded, because Boaz's Chromium build keeps no symbols. A rebuild of the same commit doesn't match:
its UUIDs differ.

## Common questions

**My spaces don't appear on my other device.** Both devices need to be signed in to iCloud with the same Apple
Account. Open Settings in Boaz to see the sync status.

**How do I bring my Arc setup over?** On Mac, choose File › Import from Arc… and select Arc's data folder. Copying
Arc's cookies (to stay signed in) is optional and stays on that Mac.

**Where is my browsing history synced?** It isn't. History and Incognito tabs stay on the device where you made them.
