# Privacy Policy

**Masque** — last updated 2026-07-29

**Short version: Masque has no servers and collects nothing.** Everything happens
on your Mac, and the only service the app talks to is Apple's iCloud, using your
own account.

## Scope

This policy covers the Masque macOS app ("the app"), distributed at
<https://github.com/stavrop/masque> and via the `stavrop/tap` Homebrew tap.

## What Masque collects

**Nothing — for the developer.** There is no Masque server, no analytics, no
telemetry, no crash reporting, no tracking, and no account with the developer.
The developer never receives your Apple ID, your password, your addresses, or any
usage data. Masque runs entirely on your Mac and communicates **only with Apple's
servers** (`idmsa.apple.com` and `*.icloud.com`) — the same ones the icloud.com
website uses — to sign in and manage your Hide My Email addresses.

## Your Apple ID credentials

- When you sign in, your Apple ID password is used in Apple's **SRP** login
  handshake. It is sent **only to Apple**, never travels in plain text, and is
  **never stored** by Masque nor transmitted to the developer.
- After a successful sign-in (including two-factor), Masque stores **only**
  Apple's session cookies and trust token in your Mac's **Keychain**, so you
  don't have to sign in on every launch. These never leave your Mac except when
  the app uses them to talk to Apple.

## Data stored locally on your Mac

- **Keychain:** Apple session cookies + trust token (above).
- **App preferences** (macOS user defaults): non-personal UI settings only, such
  as the address-list height and whether to show the welcome window.
- Your Hide My Email addresses live in **your iCloud account** — Masque displays
  them but keeps no separate copy or database.

Uninstalling (`brew uninstall --cask masque` runs the cask's `zap`, or drag the
app to the Trash and remove its container) clears these local items.

## Third parties

- **Apple.** All account and Hide My Email data is processed by Apple under
  [Apple's Privacy Policy](https://www.apple.com/legal/privacy/). Masque is not
  affiliated with Apple.
- **Optional links.** If you click "Star on GitHub" or "Buy me a coffee," your
  browser opens GitHub or Buy Me a Coffee, each with their own privacy policy.
  Masque shares no data with them.

## Children

Masque is not directed at children and collects no personal information from
anyone.

## Changes

This policy may change; updates are committed to this repository with a new
"last updated" date.

## Contact

Questions or concerns: open an issue at
<https://github.com/stavrop/masque/issues>.
