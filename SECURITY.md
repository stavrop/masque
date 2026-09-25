# Security Policy

## Supported versions

Masque is a hobby project; only the **latest release** receives security fixes.

## Reporting a vulnerability

Please report security issues **privately** using GitHub's
[**Report a vulnerability**](https://github.com/stavrop/masque/security/advisories/new)
(Security → Advisories). Please do **not** open a public issue for a vulnerability
until it has been addressed.

I'll acknowledge reports within a few days on a best-effort basis (this is a
hobby project, not a commercial product).

## What this app touches

- **Your Apple ID password** is used only in Apple's **SRP** login handshake: it
  is sent **only to Apple**, never travels in plain text, and is **never stored**
  or transmitted to the developer.
- After sign-in, Masque stores **only** Apple's session cookies and two-factor
  **trust token** in your macOS **Keychain**, to avoid re-logging in each launch.
- It talks **only** to Apple's own hosts (`idmsa.apple.com`, `setup.icloud.com`,
  `*-maildomainws.icloud.com`) to authenticate and manage your Hide My Email
  addresses.
- It stores nothing else of note (only non-personal UI preferences) and contains
  **no** telemetry, analytics, crash reporting, or third-party network calls.

## Trust & scope notes

- The bundled OAuth widget key / client id is the **public** iCloud-web value; it
  is not a secret and grants nothing on its own.
- The iCloud endpoints it calls are **private and undocumented** and may change or
  disappear without notice. This is an unofficial tool — see the README and
  [Terms](https://stavrop.github.io/masque/terms.html).
- Because the app authenticates your Apple ID and can read/rewrite its stored
  session in your Keychain, only run builds you trust. Releases are Developer
  ID-signed and **notarized**, and building from source (the documented path)
  lets you audit exactly what runs.

## App Sandbox

Masque runs in the App Sandbox under the hardened runtime, Developer ID-signed
and notarized. It holds two entitlements:

- `com.apple.security.network.client` — reaching idmsa.apple.com and iCloud.
- `com.apple.security.device.usb` — talking CTAP2 to a hardware security key,
  for Apple Accounts that use one as their second factor.

0.4 briefly shipped unsandboxed, because it obtained the assertion by running
libfido2's `fido2-assert`, and the sandbox denies both USB HID access and
spawning that binary. 0.5 speaks CTAP2 in-process instead, which the sandbox
permits with the USB entitlement, so the confinement is back and no third-party
library is involved.
