#!/usr/bin/env bash
# Builds the particle sheet the sheet presets (Leaves, Debris, Smoke Puff,
# Sparkle - engine/particle_presets.odin, #401) use from Kenney's CC0 packs
# (kenney.nl: Particle Pack, Foliage Sprites), into assets/kenney/particles/.
#
#   scripts/templates/prep_kenney_particles.sh <particle pack dir> <foliage sprites dir>
#
# 8 x 3 cells of 64 px (each image fitted in 60 px, centred):
#   row 0  leaves (Foliage Sprites, shaded 81-88)
#   row 1  a smoke puff turning to a ring (smoke 7-10), then debris (dirt 1-3, smoke 3)
#   row 2  stars (star 1, 4, 7, 8, 9, 6), a soft dot (circle 5), a flare (light 1)
# The Particle Pack's images are white on black (for additive blending):
# their brightness becomes alpha, white, so the colour over life tints them.
# Needs ImageMagick (magick).
set -euo pipefail
pp="$1/PNG"
fol="$2/PNG/Shaded"
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/assets/kenney/particles"
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
i=0
cell() { magick "$@" -resize 60x60 -background none -gravity center -extent 64x64 "$tmp/c$(printf %02d $i).png"; i=$((i + 1)); }
glow() { cell "$1" -colorspace gray -alpha off \( +clone \) -compose copy_opacity -composite -compose over -channel RGB -evaluate set 100% +channel; }
for n in 81 82 83 84 85 86 87 88; do cell "$fol/sprite_00$n.png"; done
for f in smoke_07 smoke_08 smoke_09 smoke_10 dirt_01 dirt_02 dirt_03 smoke_03; do glow "$pp/$f.png"; done
for f in star_01 star_04 star_07 star_08 star_09 star_06 circle_05 light_01; do glow "$pp/$f.png"; done
magick montage "$tmp"/c*.png -tile 8x -geometry 64x64+0+0 -background none "PNG32:$out/particles.png"
cat > "$out/License.txt" <<'LIC'
particles.png: cells from two Kenney packs (www.kenney.nl), resized and
put on one sheet (scripts/templates/prep_kenney_particles.sh):
  Particle Pack (2018) - smoke, dirt, stars, circle, light
  Foliage Sprites (2020) - the leaves

License: Creative Commons Zero, CC0
http://creativecommons.org/publicdomain/zero/1.0/
This content is free to use in personal, educational and commercial projects.
Support Kenney by crediting Kenney or www.kenney.nl (not mandatory).
LIC
echo "wrote $out/particles.png"
