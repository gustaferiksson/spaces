# Releasing Spaces

Spaces ships as a Developer ID signed and notarized app through GitHub Releases and a Homebrew cask. Installed
copies update themselves: `AppUpdater` checks `releases/latest` on launch, every 24 hours and on wake, downloads
`Spaces-<version>.zip`, verifies its code signature (team `82K3YC8HVF`, identifier `dev.gustaf.Spaces`), stages it
next to the installed app and swaps it in on quit or on "Install Spaces <version> and Relaunch" in the menu.

## How the pipeline works

`.github/workflows/release.yml` runs on a `v*` tag and calls the shared `gustaferiksson/macos-release` workflow:

```
git tag v1.2.0  →  push  →  [release.yml]
                              ├─ build.sh         (Developer ID, hardened runtime, timestamp)
                              ├─ notarytool       (Apple ID + app-specific password)
                              ├─ ditto → Spaces-1.2.0.zip
                              ├─ gh release create (attaches the zip)
                              └─ bump Casks/spaces.rb in gustaferiksson/homebrew-tap
```

The tag sets the version (`v1.2.0` → `CFBundleShortVersionString` `1.2.0`); the build number is the Actions run
number. The updater depends on three things staying in lockstep: the repo `gustaferiksson/spaces`, the tag format
`v<version>`, and the asset name `Spaces-<version>.zip` (the workflow's `name: Spaces`).

## One-time setup

The repo and its release secrets already exist from the CLI days. Before the first app release, add
`Casks/spaces.rb` to `gustaferiksson/homebrew-tap` (copy `Casks/rinse.rb`, placeholder `version`/`sha256`) and
delete `Formula/spaces.rb`, so `brew install gustaferiksson/tap/spaces` resolves to the cask. The workflow only
rewrites the cask's two lines and fails if the file is missing.

## Every release

```sh
git tag v1.0 && git push origin v1.0
gh run watch
```

Existing installs pick it up within a day, or immediately via "Check for Updates…" in the menu bar menu.

## Notes

- Local builds are stamped `<git describe>-local` and never check for updates on their own (a manual check still
  works). Debug builds never update.
- An install in a folder the user can't write to (for example a root-owned `/Applications` copy) reports that it
  can't update itself, and a manual check opens the releases page instead.
- Local release without CI: see [`SHIPPING.md`](../SHIPPING.md).
