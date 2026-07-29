# Contributing to Masque

Thanks for your interest! Masque is a small, free, open-source macOS menu bar app
for Apple Hide My Email. Bug reports, fixes, and focused features are welcome.

## Ground rules

- **It's an unofficial tool.** Masque talks to Apple's private iCloud web
  endpoints. Please keep contributions scoped to helping a user manage *their own*
  Hide My Email addresses. Nothing that scrapes, automates at scale, targets other
  accounts, or otherwise risks account safety or abuses Apple's services.
- **Never log or transmit secrets.** Passwords, 2FA codes, session tokens, and
  cookies must never be printed (the `MASQUE_DEBUG` logging deliberately prints
  only step names + HTTP status) or sent anywhere but Apple.
- Be kind in issues and reviews.

## Prerequisites

- macOS 14+ and **Xcode 26+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- The [BigInt](https://github.com/attaswift/BigInt) package resolves automatically.

## Build & run

```sh
cd macos
xcodegen generate        # regenerate Masque.xcodeproj (git-ignored — never commit it)
open Masque.xcodeproj     # ⌘R to run, ⌘U to test
```

Or from the CLI:

```sh
cd macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme Masque -destination 'platform=macOS' build   # or: test
```

### Developing without an Apple ID

Run in **mock mode** so you never touch real iCloud:

- `-mock` (or `MASQUE_MOCK=1`) — in-memory fake data. The mock 2FA code is `123456`.
- `MASQUE_MOCK_AUTHED=1` — start already signed-in (handy for UI work / screenshots).
- `MASQUE_DEBUG=1` — log each auth/API step (status codes only, never secrets) to stderr.

## Tests

`macos/Tests/SRPClientTests.swift` pins the SRP handshake (public `A`, `M1`, `M2`)
and the `s2k`/`s2k_fo` key derivations to reference vectors from the Python `srp`
library. **These must stay green.** If you change anything in `Crypto/`,
re-verify against the reference (the generator lives in the project scratchpad /
PR discussion) — byte framing here is unforgiving.

## Project layout

The UI is written against the `ICloudService` protocol, so the whole flow runs on
the mock before ever hitting Apple. The live service is an `actor`. See the
**Architecture** section of the [README](README.md) for the file map.

## Style & PRs

- Match the surrounding code — SwiftUI + small, focused types; comments explain
  *why*, not *what*.
- Keep PRs small and single-purpose; describe what changed and why.
- Update `CHANGELOG.md` (under `[Unreleased]`) for user-facing changes.
- Don't commit the generated `.xcodeproj` or `macos/build/`.

## Security issues

Please **do not** open a public issue for a vulnerability — follow
[SECURITY.md](SECURITY.md) (private GitHub advisory).

## License

By contributing, you agree that your contributions are licensed under the
project's [Apache-2.0](LICENSE) license.
