# Releasing Masque

Masque is distributed as a notarized macOS app via a Homebrew **cask** in
[stavrop/homebrew-tap](https://github.com/stavrop/homebrew-tap), with the built
`Masque.zip` attached to a GitHub Release.

## Versioning

`MAJOR.MINOR` (no patch) + build number, e.g. `0.1 (1)`. Git tags are `vMAJOR.MINOR`.
Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `macos/project.yml`.

## Steps

1. **Tag** the release on the canonical GitLab remote and the GitHub mirror:

   ```sh
   git tag -a v0.1 -m "Masque v0.1"
   git push origin v0.1        # GitLab (canonical)
   git push github v0.1        # GitHub (public mirror)
   ```

2. **Build + notarize** (needs the Developer ID cert + a notarytool credential —
   see the script header):

   ```sh
   NOTARY_PROFILE=masque-notary tools/build_macos_notarized.sh
   ```

   Prints the path to `macos/build/Masque.zip` and its **sha256**.

3. **Create the GitHub Release** and attach the zip:

   ```sh
   gh release create v0.1 macos/build/Masque.zip \
     --repo stavrop/masque --title "Masque v0.1" --notes-file <(sed -n '/## \[0.1\]/,/## \[/p' CHANGELOG.md)
   ```

4. **Update the cask** in the tap repo (`Casks/masque.rb`): set `version` and the
   `sha256` from step 2, then commit + push. Users then get it via:

   ```sh
   brew tap stavrop/tap
   brew install --cask masque
   ```

## Remotes

The local repo pushes to two remotes — `origin` (GitLab, canonical) and `github`
(public mirror). Push to both on release:

```sh
git push origin main && git push github main
```
