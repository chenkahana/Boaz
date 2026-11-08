# Security policy

## Supported versions

Security fixes go into the latest App Store release of Folio for iPhone and Mac. Older versions are not patched;
update to the latest version.

| Version | Supported |
|---|---|
| 1.x (latest) | Yes |
| Earlier builds and TestFlight betas | No |

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub:

1. Go to the repository's [Security tab](https://github.com/chenkahana/Folio/security).
2. Choose **Report a vulnerability** and describe the issue.

Include the affected app and version, the device and OS version, steps to reproduce, and the impact you expect.
A proof of concept helps.

### What to expect

- Acknowledgement within 3 business days.
- An initial assessment within 10 business days.
- Updates as the fix progresses, and credit in the release notes if you want it.

Please give us a reasonable chance to release a fix before disclosing the issue publicly.

## Scope

In scope:

- The Folio apps for iPhone and Mac, their share extension and widgets
- FolioKit, including sync and the Arc and bookmark importers
- Handling of data imported from other browsers, including cookies

Out of scope:

- Vulnerabilities in WebKit, iOS or macOS (report those to [Apple](https://security.apple.com))
- Issues on websites you visit with Folio
- Attacks that need a jailbroken device or physical access to an unlocked device
