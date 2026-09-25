# Changelog

All notable changes to Masque are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning is
MAJOR.MINOR (no patch) + a build number, matching the app's scheme.

## [Unreleased]

## [0.5] — 2026-09-25

### Changed
- **The sandbox is back, and the libfido2 dependency is gone.** 0.4 reached the
  security key by shelling out to `fido2-assert`, which meant giving up the App
  Sandbox (it denies both USB HID access and spawning that binary) and asking
  users to `brew install libfido2`. Masque now speaks CTAP2 to the key itself,
  in-process, over IOKit HID — so it runs sandboxed again with one added
  entitlement, `com.apple.security.device.usb`, and installs with no
  dependencies. The app also stays universal (Intel + Apple Silicon), which
  linking Homebrew's arm64-only libfido2 would have prevented.
- **One touch instead of two.** Every registered credential is sent in a single
  CTAP2 `allowList`, so the key selects the one it holds rather than Masque
  trying each in turn.

### Added
- `CTAPHIDDevice` — CTAPHID transport (channel allocation, packet framing,
  keepalive handling) over IOKit HID.
- `CBOR` — the subset of RFC 8949 that CTAP2 needs, encode and decode.

### Fixed
- The authenticator data no longer needs unwrapping: reading the CTAP2 response
  directly yields the raw bytes WebAuthn signs. The CBOR byte-string header that
  0.4 had to strip was an artifact of the `fido2-assert` CLI's output format.

## [0.4] — 2026-09-25

### Added
- **Sign in with a hardware security key.** Apple Accounts that have security
  keys registered never receive a six-digit code — Apple disables trusted-device
  and SMS verification entirely and instead returns a WebAuthn `fsaChallenge`.
  Masque now detects that, shows a dedicated screen naming the registered keys,
  and completes 2FA with an assertion from the attached key (a physical touch),
  posted to `/appleauth/auth/verify/security/key`.
- A **"Send a new one"** action and **per-number SMS** buttons on the 2FA screen,
  for accounts that do use codes.

### Fixed
- **No code ever arrived on some accounts.** After Apple's `409`, Masque
  immediately fired a second `PUT .../trusteddevice/securitycode`. Apple had
  already pushed a prompt with the 409, and the duplicate superseded it — the
  device showed "a sign-in was requested" and then no code sheet, forever.
  The push is now an explicit user action only.
- Failures of that push were swallowed by a `try?` and never surfaced, so the
  UI sat on a code field with no indication anything had gone wrong.
- An SMS code was verified against the trusted-device endpoint, which cannot
  accept it; SMS codes now go to `/verify/phone/securitycode`.
- `MASQUE_DEBUG=2` (raw auth bodies) silently disabled all logging, because the
  flag was compared against `"1"` exactly.

### Changed
- **The app is no longer sandboxed.** Reading an assertion off a security key
  needs the USB HID interface, which the sandbox denies. Re-sandboxing requires
  linking libfido2 in-process plus `com.apple.security.device.usb`.
- Security-key login requires **libfido2** (`brew install libfido2`).

## [0.3] — 2026-08-17

### Added
- **App icon** — a white masquerade mask on a violet squircle. Masque previously
  shipped with an empty icon set, so it showed the generic placeholder in Finder
  and the app list. The vector source lives in `tools/icon.svg`;
  `tools/make_appicon.sh` rasterises it into the asset catalog at every macOS
  size (16–512pt, @1x/@2x), straight from the vector so the small sizes stay
  crisp.

## [0.2] — 2026-07-29

### Added
- Welcome / About window shown at launch (with a "Show at startup" toggle) and
  reopenable from the menu — app info, version, a GitHub-star nudge, and a
  Buy Me a Coffee link.
- Menu items: **About Masque**, **Star on GitHub**, **Buy Me a Coffee**; an
  **About** link on the sign-in screen too.

### Changed
- Larger menu bar icon and a bigger app glyph in the welcome window.

## [0.1] — 2026-07-28

First working version: a macOS menu bar app that creates, searches, and manages
Apple Hide My Email addresses over the (unofficial) iCloud web endpoints.

### Added
- SwiftUI `MenuBarExtra` menu bar app (agent app, no Dock icon).
- Native iCloud authentication: SRP-6a login + trusted-device 2FA + trust-token
  capture, reimplemented in Swift and verified byte-for-byte against the
  reference Python `srp` library (`MasqueTests`).
- Hide My Email client: list (v2), generate, reserve, deactivate, reactivate,
  delete, and update-metadata (v1).
- Create flow: generate a candidate address, label + note, reserve.
- Search across label, note, address, and forward-to.
- Manage: edit label/note; deactivate / reactivate; delete (auto-deactivates an
  active address first, which Apple otherwise rejects).
- Persistent session: auth cookies + service context stored in the Keychain and
  silently restored (and re-validated) on launch.
- Resizable address list: screen-relative default height (~40%), drag handle,
  persisted across launches.
- Mock service (`-mock` / `MASQUE_MOCK=1`) for offline UI work.
- Step diagnostics (`MASQUE_DEBUG=1`) that never log secrets.
- GitLab CI: unsigned build + unit tests on the macOS/Xcode runner.

### Notes
- Requires **Access iCloud Data on the Web** to be enabled on the Apple ID;
  otherwise the iCloud service rejects the session (`Invalid global session`).
- Uses private, unofficial iCloud endpoints that may change without notice.
