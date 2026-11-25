# Review instructions

Boaz is a Swift app for Apple platforms (iPhone, Mac, and related targets), owned by one developer. Reviews should be short and worth reading.

## What Important means here

Reserve Important for findings that would break behavior or ship a bug to users: crashes and force-unwraps on real input, data loss or corrupt migrations, main-thread blocking, Swift concurrency races and retain cycles, leaked secrets or tokens, user data written to logs, and changes that break signing, entitlements, or the build. Style, naming, and refactoring suggestions are Nit at most.

## Cap the nits

Report at most five Nits per review.

## Do not report

- Formatting and anything CI or a linter already enforces
- `Vendor/`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`, generated Xcode projects (`*.xcodeproj`), and `*.xcassets` contents
- Test-only code that intentionally breaks production rules

## Always check

- New user-facing behavior has a test, or the pull request says why not
- Changes to storage, sync, or persistence include a migration and keep old data readable
- Network calls handle failure and offline states, and do not block the UI
- Accessibility labels exist on new controls, and layouts survive Dynamic Type
- Behavior claims in a finding cite file and line, not an inference from naming
