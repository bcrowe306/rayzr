#!/usr/bin/env bash
# The release packages of a packaged editor (scripts/package_editor.sh's
# dist/), as users download them - .github/workflows/build-packages.yml
# (the releases and the install checks, #330):
#   macos    rayzr-editor-<version>-macos.dmg            (a drag-to-install disk image:
#            the .app beside an Applications link, scripts/ci/dmg_settings.py)
#   linux    rayzr-editor-<version>-linux.tar.gz,
#            rayzr-editor-<version>-linux-x86_64.AppImage (scripts/ci/appimage_editor.sh),
#            rayzr-editor-<version>-linux-amd64.deb       (scripts/ci/deb_editor.sh)
#   windows  rayzr-editor-<version>-windows.zip
# Written to the current folder.
#   scripts/ci/archive_editor.sh <version> [dist] [app name]
# macOS: the disk image is made by dmgbuild (pinned with hashes:
# scripts/ci/dmgbuild_requirements.txt), installed into a venv under
# $RUNNER_TEMP (or $TMPDIR) unless $DMGBUILD names one. It isn't signed here:
# with a Developer ID, the release signs the app first and the disk image
# after (scripts/ci/sign_macos.sh, docs: RELEASING.md).
set -euo pipefail
version="$1"
dist="${2:-dist}"
name="${3:-Rayzr Editor}"
scripts="$(cd "$(dirname "$0")" && pwd)"
base="rayzr-editor-$version"

# make_dmg APP VOLUME_NAME OUT: the drag-to-install disk image.
make_dmg() {
	[ -d "$1" ] || { echo "no $1" >&2; exit 1; }
	local dmgbuild="${DMGBUILD:-}"
	if [ -z "$dmgbuild" ]; then
		local venv="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/rayzr-dmgbuild-1.6.7"
		if [ ! -x "$venv/bin/dmgbuild" ]; then
			python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' ||
				{ echo "dmgbuild needs Python 3.10+ (python3 is $(python3 --version 2>&1))" >&2; exit 1; }
			python3 -m venv "$venv"
			"$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: \
				-r "$scripts/dmgbuild_requirements.txt"
		fi
		dmgbuild="$venv/bin/dmgbuild"
	fi
	local repo
	repo="$(cd "$scripts/../.." && pwd)"
	rm -f "$3"
	"$dmgbuild" -s "$scripts/dmg_settings.py" -D app="$1" -D background="$repo/branding/dmg/background.png" "$2" "$3"
}

case "$(uname -s)" in
	Darwin)
		base="$base-macos"
		make_dmg "$dist/$name.app" "$name $version" "$base.dmg" ;;
	Linux)
		base="$base-linux"
		tar -C "$dist" -czf "$base.tar.gz" rayzr-editor-linux
		"$scripts/appimage_editor.sh" "$version" "$dist"
		mv "$dist/Rayzr_Editor-$version-x86_64.AppImage" "$base-x86_64.AppImage"
		"$scripts/deb_editor.sh" "$version" "$dist"
		mv "$dist"/rayzr-editor_*_amd64.deb "$base-amd64.deb" ;;
	MINGW*|MSYS*|CYGWIN*)
		base="$base-windows"
		here="$PWD"
		(cd "$dist" && 7z a -bd "$here/$base.zip" rayzr-editor-windows > /dev/null) ;;
	*) echo "Unknown platform $(uname -s)" >&2; exit 1 ;;
esac
ls -la "$base"*
