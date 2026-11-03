# Releasing

Every build is made by GitHub Actions (`.github/workflows/release.yml`).

## Dev builds: every merge to main

Each feature or fix lands on `main` (merge its branch / pull request). When
CI passes on that push, the release workflow builds every platform and
publishes a **pre-release** tagged on that commit:

```
v0.1.0-dev.142        <VERSION>-dev.<main's commit count>
```

`VERSION` (repository root) is the **next** release. Nothing to do by hand:
merge, and the dev build appears under Releases about half an hour later
(Actions > Release shows it building). A CI failure on main means no dev build
for that commit; re-running a passed CI doesn't build twice. Dev-build editors
check for newer dev builds (and releases) at startup and offer them in the
status bar.

## Releases

When a dev build is good enough to ship, tag its commit with `VERSION` and
push the tag:

```sh
git tag v0.1.0 <commit>     # or v0.1.0-beta.1 (a pre-release)
git push origin v0.1.0
```

Then bump `VERSION` (`0.2.0`) on main: dev builds stop until it's bumped
(they'd sort below the release). Release editors only offer releases.

Before tagging, install the candidate on fresh machines: the **Install
check** workflow (Actions > Install check > Run workflow) and the checklist
of what it can't check ([Install checks](docs/contributing/install-checks.md)).

## What a build contains

The workflow builds (`build-packages.yml`, shared with the install checks):

1. the game runners on macOS, Linux and Windows, and the web runner;
2. the editor on each platform, with **every** platform's runners inside (any
   editor exports macOS, Windows, Linux and web games);
3. a GitHub Release with the packages and `SHA256SUMS.txt` (and the same
   files on the website's download page, below):

| Platform | Files |
|---|---|
| macOS (Apple silicon) | `rayzr-editor-<version>-macos.dmg` |
| Windows (x64) | `rayzr-editor-<version>-windows.zip` |
| Linux (x64) | `rayzr-editor-<version>-linux-x86_64.AppImage`, `-amd64.deb`, `.tar.gz` |

The version (the tag without `v`) is built into the editor and the runners
(`RAYZR_RELEASE`: the editor's title and `--version`, `project.json`'s
`engine_version`, the update check). A dry run without publishing: Actions >
Release > Run workflow (a version, no tag), or push to `release-dryrun`.

## The website (rayzr.app)

After the GitHub Release, the same workflow updates
[rayzr.app](https://rayzr.app):

1. `scripts/ci/publish_r2.py` uploads the packages to the downloads bucket
   (Cloudflare R2, served at `downloads.rayzr.app`): releases under
   `releases/v<version>/`, dev builds under `dev/v<version>/`, and
   `manifest.json`. It keeps the **3 newest releases** (semver order) and
   the **latest dev build**; older ones are deleted (they stay on GitHub).
2. It calls the website's workflow (`bcrowe306/rayzr_website`,
   `.github/workflows/site.yml`): the site syncs the manifest, builds the
   docs of every kept version from that version's tag (dev: `main`) with
   the tag's own `scripts/docs/export_site.py`, runs its tests, deploys to
   Cloudflare Pages and verifies the live site (`scripts/verify-deploy.mjs`).

So a tag puts the release on the download page and its docs at
`rayzr.app/docs/` (the previous release moves to `/docs/v<version>/`), and
every merge refreshes the dev build and `/docs/dev/`. Pull requests build
the site with their docs and deploy a preview (`.github/workflows/docs.yml`).
The docs themselves: [docs/contributing/docs.md](docs/contributing/docs.md).

Repository secrets: `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY` (the upload) and `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID` (the deploy, also set in the website repository).

Every push and pull request runs CI (`.github/workflows/ci.yml`): the editor,
runner and Play binary build, and the unit tests run, on all three platforms;
on Linux the runner plays the demo project and the packaged editor is
smoke-tested (`scripts/test_package.sh`). The editor's UI drives
(`scripts/editor_drive.sh`) stay local: they need a GPU.

## Signing (optional)

Without these secrets the packages are unsigned (macOS: ad-hoc signed - users
right-click > Open the first time; Windows: SmartScreen warns).

**macOS** - Developer ID + notarization (`scripts/ci/sign_macos.sh`), needs an
Apple Developer account. Repository secrets:

- `MACOS_CERTIFICATE` - the *Developer ID Application* certificate exported
  as `.p12`, base64 (`base64 -i cert.p12 | pbcopy`)
- `MACOS_CERTIFICATE_PASSWORD` - its password
- `MACOS_SIGNING_IDENTITY` - e.g. `Developer ID Application: Your Name (TEAMID)`
- `MACOS_NOTARY_APPLE_ID`, `MACOS_NOTARY_TEAM_ID`, `MACOS_NOTARY_PASSWORD`
  (an app-specific password from appleid.apple.com)

**Windows** - a code-signing certificate (`scripts/ci/sign_windows.sh`):

- `WINDOWS_CERTIFICATE` - the `.pfx`, base64
- `WINDOWS_CERTIFICATE_PASSWORD`

## Building packages locally

```sh
task editor:package VERSION=0.1.0   # dist/: the .app (macOS) or a folder
task editor:package:test            # runs it from outside the checkout
```

The static libraries the editor links are built by `scripts/build_imgui.sh`,
`scripts/build_lua.sh` and `scripts/build_cmark.sh` (the macOS ones are in the
repo; CI builds the others: `scripts/ci/setup_deps.sh`).
