# Masque

A small macOS **menu bar app** for Apple **Hide My Email**: create new addresses,
search your existing ones, and manage them (edit label/note, deactivate,
reactivate, delete) — all from the menu bar.

## Install

```sh
brew tap stavrop/tap
brew install --cask masque
```

Or grab the notarized `Masque.zip` from the
[latest release](https://github.com/stavrop/masque/releases/latest).

## Features

- 🔐 **Native iCloud sign-in** — Apple ID + password + two-factor, implemented
  in Swift (SRP-6a). The password never leaves your Mac in the clear; only
  Apple's trust token is stored (Keychain), so subsequent logins skip 2FA.
- 💾 **Persistent session** — the authenticated session is saved to the Keychain
  and silently restored on the next launch (re-validated with a live call); no
  re-login until Apple actually expires it.
- ➕ **Create** — generate a candidate address, label it + add a note, reserve it.
- 🔎 **Search** — filter by label, note, address, or forward-to address.
- 🛠 **Manage** — edit label/note, deactivate / reactivate, delete (auto-deactivates
  first, since Apple won't delete an active address).
- 📐 **Resizable list** — the address list height defaults to ~40% of your screen
  and is drag-resizable (remembered across launches).

## Support

Masque is free and open-source, built in spare time. If it earns a spot in your
menu bar, two small things help more than you'd think:

- ⭐️ **[Star it on GitHub](https://github.com/stavrop/masque)** — stars are how
  other people find it, and they genuinely make my day.
- ☕️ **[Buy me a coffee](https://www.buymeacoffee.com/stavrop)** — a small tip
  keeps the late-night bug-fixing caffeinated and the updates coming.

No pressure at all — even telling a friend means a lot. Thank you! 🙏

## ⚠️ Requirement: "Access iCloud Data on the Web" must be ON

Masque reaches Hide My Email through Apple's iCloud **web** service endpoints (the
same ones icloud.com uses). Those services reject any web session unless your
Apple ID has **Access iCloud Data on the Web** enabled — otherwise every request
fails with `Invalid global session` and Masque will tell you so.

Turn it on (once), on a trusted device:

- **iPhone/iPad:** Settings → *your name* → iCloud → **Access iCloud Data on the Web**
- **Mac:** System Settings → *your name* → iCloud → **Access iCloud Data on the Web**

It can't be enabled from a browser — Apple only exposes a "Manage on Device…" link
there. This is a deliberate privacy control; with it off, no web-based tool
(Masque, the browser extension, or icloud.com data views) can reach your data.

## ⚠️ Unofficial endpoints

Apple publishes **no** public API for Hide My Email. Masque talks to the same
private endpoints (`idmsa.apple.com/appleauth`, `setup.icloud.com`,
`*-maildomainws.icloud.com`) that the icloud.com web client and the well-known
"Hide My Email" browser extension use. They can change or break without notice.
Use it on your own account, at your own discretion.

## Build & run

Requires Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`); the [BigInt](https://github.com/attaswift/BigInt)
package is resolved automatically.

```sh
cd macos
xcodegen generate          # regenerate Masque.xcodeproj (git-ignored)
open Masque.xcodeproj       # ⌘R to run, ⌘U to test
```

Or from the CLI:

```sh
cd macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme Masque -destination 'platform=macOS' build   # or: test
```

### Mock vs. live

- **Live (default):** talks to real iCloud. Sign in with your Apple ID + 2FA.
- **Mock:** launch with `-mock` (or `MASQUE_MOCK=1`) for in-memory fake data, no
  network — handy for UI work. In mock mode the 2FA code is `123456`.
- **Debug logging:** set `MASQUE_DEBUG=1` to log each auth/API step (status codes
  only — never passwords, codes, tokens, or cookie values) to stderr.

## Architecture

```
macos/App/
  MasqueApp.swift              MenuBarExtra scene; picks mock/live service
  Models/HMEAddress.swift      the HME record + search matching
  ViewModels/AppState.swift    @MainActor state machine (screens, intents)
  Views/                       MenuRoot, Login, TwoFactor, AddressList, Row, Create, Edit
  Services/
    ICloudService.swift        protocol the UI depends on (+ ICloudError)
    MockICloudService.swift    in-memory fake
    ICloudLiveService.swift    actor: SRP + 2FA + accountLogin + session persistence
    ICloudLiveService+HME.swift  Hide My Email endpoints (list=v2, rest=v1)
    KeychainStore.swift        trust token + persisted session bundle
    Crypto/
      CryptoUtils.swift        SHA-256, PBKDF2 (s2k/s2k_fo), long_to_bytes/pad
      SRPClient.swift          SRP-6a (pysrp-exact: NG_2048, SHA-256, no_username_in_x)
macos/Tests/
  SRPClientTests.swift         pins A / M1 / M2 / s2k / s2k_fo to pysrp vectors
```

The UI is written against the `ICloudService` protocol, so the whole flow runs on
the mock before ever hitting Apple. The live service is an `actor`, so session
state (cookies, tokens, the maildomains host) is race-free. The SRP handshake is
verified byte-for-byte against the reference Python `srp` library in the tests.

## Known limitations / ideas

- Trusted-device 2FA only (no SMS-code path yet).
- No global hotkey / quick-create shortcut yet.
- Custom email domains are not surfaced (only `@icloud.com` addresses).

See [CHANGELOG.md](CHANGELOG.md) for release notes.
