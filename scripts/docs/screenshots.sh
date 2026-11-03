#!/usr/bin/env bash
# Refreshes the documentation's screenshots: runs the docs_*.drive and
# tutorial_*.drive editor drives (tests/drive/) and copies each screenshot - with its
# .annotations.json callouts, written by the drive's `annotate` lines - into
# docs/images/<name>.png (the drive's "NN_" prefix dropped). The docs site
# draws the numbered callouts over the image and lists their labels below
# it (scripts/docs/export_site.py). Needs a GPU and, on macOS, an awake
# display, so it runs locally, not in CI; commit docs/images/ afterwards.
#   scripts/docs/screenshots.sh                    # every docs_* and tutorial_* drive
#   scripts/docs/screenshots.sh docs_editor_tour   # selected drives
set -euo pipefail
cd "$(dirname "$0")/../.."
drives=("$@")
if [ ${#drives[@]} -eq 0 ]; then
	for d in tests/drive/docs_*.drive tests/drive/tutorial_*.drive; do drives+=("$(basename "$d" .drive)"); done
fi
./scripts/editor_drive.sh "${drives[@]}"
mkdir -p docs/images
for d in "${drives[@]}"; do
	for png in editor_screenshots/drive/"$d"/[0-9][0-9]_*.png; do
		[ -e "$png" ] || continue
		name="$(basename "$png" .png)"; name="${name#[0-9][0-9]_}"
		cp "$png" "docs/images/$name.png"
		ann="${png%.png}.annotations.json"
		if [ -e "$ann" ]; then cp "$ann" "docs/images/$name.annotations.json"; else rm -f "docs/images/$name.annotations.json"; fi
		echo "docs/images/$name.png"
	done
done
