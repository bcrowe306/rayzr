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
`engine_version`, the update check).

The editor's auto-updater (`editor/update_install.odin`, [docs/editor/updates.md](docs/editor/updates.md))
reads `manifest.json` below and relies on this layout: the `.dmg` holds one
`.app`, the Windows `.zip` and Linux `.tar.gz` one top-level
`rayzr-editor-<platform>/` folder with `rayzr-editor[.exe]` inside, and every
file has its `sha256` in the manifest. Changing a package's layout or name
means changing the updater too (an older editor must still update to it). A dry run without publishing: Actions >
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

## The macOS disk image

`scripts/ci/archive_editor.sh` makes `rayzr-editor-<version>-macos.dmg` with
[dmgbuild](https://github.com/dmgbuild/dmgbuild) (headless, no Finder
scripting; pinned with hashes in `scripts/ci/dmgbuild_requirements.txt`,
installed into a throwaway venv). Settings: `scripts/ci/dmg_settings.py`.

- Volume **Rayzr Editor <version>**, its icon the app's (`AppIcon.icns`).
- A 640×400 icon-view window, no toolbar, sidebar, path or status bar:
  **Rayzr Editor.app** on the left, an **Applications** link
  (`-> /Applications`) on the right, icons 128pt.
- The background (`branding/dmg/background.png` and `@2x`, made by
  `scripts/ci/dmg_background.py`): an arrow from the app to Applications
  and "Drag Rayzr Editor to Applications". Move an icon and the arrow
  there too (the coordinates are in both files).
- ULFO (LZFSE) compression: macOS 10.11+, the editor needs 12.0.

## Signing (optional)

Without these secrets the packages are unsigned (macOS: an ad-hoc signed app
on an unsigned disk image - users right-click > Open the first time;
Windows: SmartScreen warns).

**macOS** - Developer ID + notarization (`scripts/ci/sign_macos.sh`; the
`package` job of `build-packages.yml`), in this order:

1. the app: every dylib and executable inside signed, inside out, then the
   app (hardened runtime, secure timestamp); notarized
   (`notarytool submit --wait`), the ticket stapled to the app;
2. the disk image made with that stapled app (**Archive**);
3. the disk image signed (`codesign --timestamp`), notarized, stapled and
   checked with `spctl -a -t open --context context:primary-signature`.

A notarization that isn't *Accepted* fails the build and prints
`notarytool log`. The certificate lives in a temporary keychain, deleted
when the script exits, also on a failure. No entitlements: the editor and
the runners don't JIT (Lua 5.4 is an interpreter) or load unsigned code
(every library is in the signed bundle). `SIGN_DRY_RUN=1
scripts/ci/sign_macos.sh <app or dmg>` prints the commands without a
certificate. `scripts/ci/install_check.sh` on a signed `.dmg` checks the
disk image's signature and both tickets.

### Setting up macOS signing

Needs an Apple Developer Program membership. Six repository secrets
(Settings > Secrets and variables > Actions):

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | The **Developer ID Application** certificate *with its private key*, exported from Keychain Access as `.p12`, base64 (`base64 -i cert.p12 \| pbcopy`). Not an *Apple Development* or *Apple Distribution* certificate: notarization rejects those, and `sign_macos.sh` stops before uploading. |
| `MACOS_CERTIFICATE_PASSWORD` | The password chosen when exporting the `.p12`. |
| `MACOS_SIGNING_IDENTITY` | The certificate's name exactly as `security find-identity -v -p codesigning` prints it: `Developer ID Application: Your Name (TEAMID)`. |
| `MACOS_NOTARY_APPLE_ID` | The Apple ID (email) of the developer account, for `notarytool`. |
| `MACOS_NOTARY_TEAM_ID` | The team id: 10 characters (Apple Developer > Membership details; also the `(TEAMID)` in the identity). |
| `MACOS_NOTARY_PASSWORD` | An app-specific password for that Apple ID (account.apple.com > Sign-In and Security > App-Specific Passwords), not the account password. |

With `MACOS_CERTIFICATE` set the release signs; leave all six empty to stay
unsigned. A first check: Actions > Release > Run workflow (a dry run), then
`scripts/ci/install_check.sh` on the `.dmg` it built (the Install check
workflow builds its own, unsigned).

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
