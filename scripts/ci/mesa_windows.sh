#!/usr/bin/env bash
# OpenGL for CI's Windows runners (#329: the template play-throughs), which
# have no GPU driver: Mesa's llvmpipe (software OpenGL 4.5) from
# pal1000/mesa-dist-win - a pinned release, checked against its SHA-256 -
# with a copy of the runner in a folder of its own (Windows loads the
# opengl32.dll next to an exe first). Never shipped: CI only.
#
#   scripts/ci/mesa_windows.sh bin/runners/windows/runner.exe "$RUNNER_TEMP/glrunner"
#   GALLIUM_DRIVER=llvmpipe "$RUNNER_TEMP/glrunner/runner.exe" ...
# (Runner "-": the DLLs only - the install checks copy them next to an
# installed editor's exes, scripts/ci/install_check.sh --gl-dlls.)
set -euo pipefail
runner="$1"; out="$2"
MESA=26.2.4
SHA256=351fc8c8b695878ffb3eaa044b3ead08672a48b1a045e3c3e3975811df0f6695
tmp="$(cygpath -m "$RUNNER_TEMP" 2> /dev/null || echo "$RUNNER_TEMP")" # (D:/a/_temp: bash and 7z alike)
archive="$tmp/mesa3d-$MESA-release-msvc.7z"
curl -fsSL --retry 3 -o "$archive" "https://github.com/pal1000/mesa-dist-win/releases/download/$MESA/mesa3d-$MESA-release-msvc.7z"
echo "$SHA256  $archive" | sha256sum -c -
mkdir -p "$out" "$tmp/mesa"
7z x -y -o"$tmp/mesa" "$archive" > /dev/null
# (The release's x64/ folder: opengl32.dll, libgallium_wgl.dll and the rest.)
found=0
while IFS= read -r dll; do cp "$dll" "$out/"; found=1; done < <(find "$tmp/mesa" -ipath '*/x64/*.dll')
[ $found = 1 ] && [ -f "$out/opengl32.dll" ] || { echo "::error::no x64/opengl32.dll in mesa3d-$MESA-release-msvc.7z"; exit 1; }
[ "$runner" = - ] || cp "$runner" "$out/"
ls "$out"
