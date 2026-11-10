# Updates

The editor keeps itself up to date. It looks for a newer version, downloads
it in the background, checks it, and installs it when you restart or quit.

## When it checks

- **At startup**, unless **Settings > General > Check for Updates** is off.
- From **Help > Check for Updates**, at any time. This one also tells you in
  the console when you're up to date.

It reads the downloads site's list of versions
(`https://downloads.rayzr.app/manifest.json`). Which versions you're offered
depends on what you run:

| You run | You're offered |
|---|---|
| A release (`1.0.0`) | Newer releases. |
| A beta (`1.1.0-beta.1`) | Newer betas and releases. |
| A dev build (`1.1.0-dev.925`, one per change to `main`) | The newest dev build, and newer releases. |
| An editor built from a source checkout | Nothing at startup. **Check for Updates** links the release page. |

## The status bar

A newer version shows at the bottom of the window:

| It shows | What it means | Click it to |
|---|---|---|
| **Update 1.2.0 available - Download** | A newer version is out, and **Download Updates Automatically** is off. | Download it. |
| **Downloading 1.2.0... 42%** | It's downloading, being checked and unpacked. Keep working. | |
| **Restart to update to 1.2.0** | It's ready. | Quit, install it and start the new version, on the same project. |
| **Install 1.2.0** | The `.deb` is downloaded and checked (Debian / Ubuntu installs). | Open it in your software installer. |
| **Update 1.2.0 failed** | Something went wrong: the tooltip says what. Nothing was changed. | Open the downloaded package's folder (or the release page), to install it by hand. |

**Restart to update** asks about unsaved scenes, scripts and levels first,
the same way quitting does. **Cancel** keeps the editor open, and the update
stays ready.

If you don't restart, the update installs when you quit, and the next start
is the new version.

## What it replaces

| Your install | What's updated |
|---|---|
| macOS: the app from the `.dmg` | The `.app` itself, where you put it (usually Applications). |
| Windows: the folder from the `.zip` | The `rayzr-editor-windows` folder. A small helper waits for the editor to close, then swaps it. |
| Linux: the AppImage | The `.AppImage` file. |
| Linux: the folder from the `.tar.gz` | The `rayzr-editor-linux` folder. |
| Linux: the `.deb` (`/opt/rayzr-editor`) | Not replaced: installing needs administrator rights. **Install** opens the downloaded `.deb`. |

Your projects, settings, plugins and workspaces aren't touched. They live
outside the install.

## Safety

- **The checksum.** Every download is checked against the SHA-256 the
  downloads site lists for it. A download that doesn't match is deleted and
  nothing is installed.
- **macOS: the signature.** The new app must have a valid code signature
  from the same developer team as the app you're running.
- **The previous version is kept.** The update is unpacked next to your
  install first, then swapped in with two renames. The version it replaced
  stays beside it (hidden: `.Rayzr Editor.app.rayzr-previous`,
  `.rayzr-editor-linux.rayzr-previous`, ...). If the swap fails, the old one
  is put back.
- **Roll back.** **Help > Roll Back to 1.1.0** restarts into the version
  the last update replaced (it asks about unsaved work first). Rolling back
  again returns to the newer one.
- **Problems after quitting.** If installing fails after the editor has
  closed, the next start says why in the console.

The editor needs to be able to write to its install's folder. If it can't
(for example an app in a folder owned by another user), the update fails
with that message and you can install the downloaded package by hand.

## Settings

In **Settings > General**:

| Option | What it does |
|---|---|
| **Check for Updates** | At startup, looks for a newer Rayzr Editor and shows it in the status bar. |
| **Download Updates Automatically** | Downloads a newer version in the background, then shows **Restart to update**. Off: the status bar's **Download** button starts it. |

## Files

The download and the updater's notes are in `~/.config/rayzr_editor/updates`
(on Windows, under your user folder):

| File | What it is |
|---|---|
| `download/` | The last downloaded package. The next update replaces it. |
| `previous.txt` | The version **Roll Back** returns to. |
| `last_error.txt` | Why the last install failed, if it did. It's shown at the next start, then removed. |
