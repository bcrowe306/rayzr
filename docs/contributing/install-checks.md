# Install checks

Before a release, the packages are installed on fresh machines and used the
way a new user would: install, make a project from a template, Play it,
export it to every target and run the exports. Most of that is scripted in
CI; a few checks need real hardware and stay manual (the checklist below).

## In CI: the Install check workflow

`.github/workflows/install-check.yml` builds the packages of a commit exactly
as a release does (`build-packages.yml`, which `release.yml` also calls;
unsigned, as the releases are until 1.0), then installs each one on a fresh
runner or container and runs `scripts/ci/install_check.sh` on it:

| Machine | Package | How it's installed |
|---|---|---|
| macOS 14, macOS 15 (Apple silicon) | `.dmg` | mounted, its layout checked (the `Applications` link, Finder's `.DS_Store` and background), the app copied out, Gatekeeper's verdict noted, the quarantine removed (a user's right-click > **Open**); when signed: the disk image's signature (`spctl`) and both notarization tickets (`stapler validate`) |
| Windows Server 2022, 2025 | `.zip` | extracted with `Expand-Archive` |
| Ubuntu 22.04, 24.04 | `.deb`, `.AppImage`, `.tar.gz` | `apt-get install ./file.deb`; the AppImage run (without FUSE: `--appimage-extract-and-run`); untarred |
| Debian 12, Fedora (containers, pinned by digest) | `.deb` (Debian), `.AppImage`, `.tar.gz` | the same, on a bare image plus Xvfb |

Then, with the installed editor only (the checkout gives the test drives,
never a binary):

1. **What the binaries need from the machine** - macOS: the signature, every
   library the system's or the bundle's, no binary needing a newer macOS than
   `Info.plist` says; Linux: glibc (2.35 at most: Ubuntu 22.04), `ldd`, the
   libraries raylib loads when it starts (OpenGL, X11, ALSA, Xrandr,
   Xcursor, Xi, Xinerama); Windows: no DLL outside Windows (the Visual C++
   runtime is linked statically). `scripts/ci/binary_deps.py` reads the
   ELF / PE files.
2. `--version`, then the bundled runner plays the bundled demo project.
3. `tests/package/install_create.drive`: Help > Welcome > a **Platformer**
   project.
4. `tests/package/install_play_export.drive`: Play (the bundled runner), then
   Export to macOS, Linux, Windows, the web and - when the machine has the
   Android SDK (build tools 34, android-34) and Java 17+ - Android.
5. The exports run: this OS's game plays 60 frames and dumps its scene; the
   web export plays in headless Chrome (Node 22+); the APK is checked
   (signed with the debug key, its package id, the runner and the game
   inside).

Each step prints `PASS`, `FAIL`, `SKIP` (with why) or `NOTE`, and each
package ends with a summary (also on the run's summary page; the logs and
screenshots are the job's artifact). GitHub's macOS VMs have no accelerated
OpenGL, so there the steps that open a window say `SKIP` - run them on a Mac
(below). The containers have no Android SDK or Chrome: those steps say
`SKIP` there too.

It runs by hand (**Actions > Install check > Run workflow**) and on pull
requests that change the packaging (`release.yml`, `build-packages.yml`,
`scripts/package_*`, `scripts/ci/`, the runner builds, `tests/package/`).
Not on every pull request: it builds every package first, as long as a
release build. It publishes nothing.

Locally, on any package:

```sh
scripts/ci/install_check.sh rayzr-editor-<version>-macos.dmg --work /tmp/install_check
```

## By hand, before a release

The checks CI can't do. Tick them for the release candidate (a dev build or
a `release-dryrun` build) and note what you ran them on in the release's
notes.

- [ ] **A Mac with a display** (CI's Macs have no OpenGL): run
      `scripts/ci/install_check.sh` on the `.dmg` - every step should pass,
      none skipped except what the Mac lacks (Android SDK, Chrome).
- [ ] **The oldest macOS the app says it runs on** (`LSMinimumSystemVersion`,
      macOS 12) and one between it and CI's (macOS 13): download the `.dmg`
      in a browser, drag the app to Applications, right-click > **Open**,
      make a project from a template, Play, export.
- [ ] **An exported macOS game on an Intel Mac**, if you have one (the
      editor is Apple silicon only; the macOS runner is universal).
- [ ] **Windows 10 and Windows 11 desktops** (CI runs Windows Server, with a
      software OpenGL): unzip, start the editor, choose **More info > Run
      anyway** at SmartScreen (unsigned until 1.0), make a project, Play,
      export, run the exported `.exe` on another PC without the editor.
- [ ] **A Linux desktop with a GPU** (Wayland session: the editor runs on
      XWayland): the AppImage from the file manager, the `.deb` from the
      applications menu.
- [ ] **Android on a real device**: export the Platformer project to
      Android, `adb install` the APK (or copy it over and allow unknown
      apps), play it - touch controls, sound, back button, rotate, leave and
      come back. Once with a release keystore (Export settings) and the AAB
      if you ship to Google Play (the first AAB export downloads bundletool
      into `~/.config/rayzr_editor/tools`, so be online for it).
- [ ] **The web export in a real browser** (Chrome, Firefox, Safari), served
      by File > Export > **Open Web Export in Browser** and from a web host.
