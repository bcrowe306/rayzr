#!/usr/bin/env bash
# The release packages of a packaged editor (scripts/package_editor.sh's
# dist/), as users download them - .github/workflows/build-packages.yml
# (the releases and the install checks, #330):
#   macos    rayzr-editor-<version>-macos.dmg            (the .app on a disk image)
#   linux    rayzr-editor-<version>-linux.tar.gz,
#            rayzr-editor-<version>-linux-x86_64.AppImage (scripts/ci/appimage_editor.sh),
#            rayzr-editor-<version>-linux-amd64.deb       (scripts/ci/deb_editor.sh)
#   windows  rayzr-editor-<version>-windows.zip
# Written to the current folder.
#   scripts/ci/archive_editor.sh <version> [dist] [app name]
set -euo pipefail
version="$1"
dist="${2:-dist}"
name="${3:-Rayzr Editor}"
scripts="$(cd "$(dirname "$0")" && pwd)"
base="rayzr-editor-$version"
case "$(uname -s)" in
	Darwin)
		base="$base-macos"
		hdiutil create -volname "$name" -srcfolder "$dist/$name.app" -ov -format UDZO "$base.dmg" ;;
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
