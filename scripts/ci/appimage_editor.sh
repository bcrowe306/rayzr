#!/usr/bin/env bash
# Linux: wraps the packaged editor (scripts/package_editor.sh's
# dist/rayzr-editor-linux) in an AppImage - one file users download, mark
# executable and run (FUSE, or --appimage-extract-and-run without it).
#   scripts/ci/appimage_editor.sh <version> [dist]
set -euo pipefail
cd "$(dirname "$0")/../.."
version="$1"
dist="${2:-dist}"
src="$dist/rayzr-editor-linux"
[ -x "$src/rayzr-editor" ] || { echo "no packaged editor in $src" >&2; exit 1; }

app="$dist/RayzrEditor.AppDir"
rm -rf "$app"
mkdir -p "$app/usr/lib/rayzr-editor"
cp -R "$src/." "$app/usr/lib/rayzr-editor/"
cp editor/assets/icon.png "$app/rayzr-editor.png"
cat > "$app/rayzr-editor.desktop" <<-EOF
	[Desktop Entry]
	Type=Application
	Name=Rayzr Editor
	Comment=2D game editor
	Exec=rayzr-editor
	Icon=rayzr-editor
	Categories=Development;Game;
	Terminal=false
	X-AppImage-Version=$version
EOF
cat > "$app/AppRun" <<-'EOF'
	#!/bin/sh
	# The editor finds its runners, fonts and language server next to itself.
	here="$(dirname "$(readlink -f "$0")")"
	exec "$here/usr/lib/rayzr-editor/rayzr-editor" "$@"
EOF
chmod +x "$app/AppRun"

# appimagetool and the AppImage runtime it puts in front of the image: pinned
# releases, checked against their SHA-256 (appimagetool would otherwise
# download the runtime's "continuous" build).
TOOL_VERSION=1.9.1
TOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_VERSION=20251108
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
fetch() { # URL FILE SHA256
	[ -f "$2" ] && echo "$3  $2" | sha256sum -c - > /dev/null 2>&1 && return
	curl -fsSL --retry 3 -o "$2" "$1"
	echo "$3  $2" | sha256sum -c -
}
tool="$dist/appimagetool-$TOOL_VERSION"
runtime="$dist/appimage-runtime-$RUNTIME_VERSION"
fetch "https://github.com/AppImage/appimagetool/releases/download/$TOOL_VERSION/appimagetool-x86_64.AppImage" "$tool" "$TOOL_SHA256"
fetch "https://github.com/AppImage/type2-runtime/releases/download/$RUNTIME_VERSION/runtime-x86_64" "$runtime" "$RUNTIME_SHA256"
chmod +x "$tool"
# (--appimage-extract-and-run: no FUSE needed, e.g. in CI containers.)
ARCH=x86_64 "$tool" --appimage-extract-and-run --runtime-file "$runtime" "$app" "$dist/Rayzr_Editor-$version-x86_64.AppImage"
echo "Built $dist/Rayzr_Editor-$version-x86_64.AppImage"
