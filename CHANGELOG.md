# Changelog

All notable changes to Masque are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning is
MAJOR.MINOR (no patch) + a build number, matching the app's scheme.

## [Unreleased]

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
