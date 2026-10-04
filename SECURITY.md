# Security Policy

Evergreen Compose (`evergreen-compose`) is experimental software under active
development. It connects Lisp application code to a shared Android Compose
runtime and includes JNI calls, APK packaging, private app state, network
requests and native libraries. Bugs at these boundaries can have security
consequences even when they first appear as ordinary crashes or incorrect UI
behavior. Applications and runtime bundles must come from trusted sources;
Evergreen Compose does not sandbox untrusted Lisp code.

## Supported versions

Security fixes are developed on `main` and, when practical, released for the
most recent tagged version.

| Version | Security updates |
| --- | --- |
| `main` | Yes |
| Latest `0.0.x` release | Best effort |
| Older releases | No |

The `0.0.x` series does not yet make a stability or long-term-support promise.
Users should expect to update to receive fixes.

## Report a vulnerability

Please report suspected vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/atgreen/evergreen-compose/security/advisories/new).
If that form is unavailable, email `green@moxielogic.com` with the subject
`Evergreen Compose security report`.

Do not open a public issue for a vulnerability that has not yet been disclosed.
Include, when available:

- the affected revision or release;
- the host operating system, EGCL version, Android version, device ABI, and
  Compose runtime bundle version;
- a minimal reproducer or malformed input;
- the observed impact and why it crosses a security boundary;
- whether the behavior involves JNI, APK signing, permissions, saved state,
  network data, WebView, media, or a bundled native library; and
- any proposed disclosure date or other coordination constraints.

You should receive an acknowledgement after the maintainer has reviewed the
report. Because Evergreen Compose is an experimental, volunteer-maintained project, no fixed
response or remediation time is promised. The maintainer will coordinate the
investigation, credit, fix, and disclosure with the reporter whenever possible.

## Public hardening reports

Crashes, incorrect results, denial-of-service behavior, and unsafe-code findings
that do not contain undisclosed security information may be filed with the
[bug report form](https://github.com/atgreen/evergreen-compose/issues/new?template=bug.yml).
When uncertain, use the private reporting channel.
