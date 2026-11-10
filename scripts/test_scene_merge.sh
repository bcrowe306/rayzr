#!/usr/bin/env bash
# The scene merge driver end to end (#293): a git repository with a template
# project, two branches each changing the same scene, `git merge` through
# `editor --merge-scene` (set up as Tools > Set Up Scene Merging does):
#   1. different fields of one node: merged cleanly, both changes in;
#   2. the same field: a conflict - ours kept, <scene>.merge.json written,
#      git reports the file as conflicted.
#   scripts/test_scene_merge.sh [bin/editor]
# The repository is made in a new temporary folder (left there: its path is
# printed).
set -euo pipefail
cd "$(dirname "$0")/.."
editor="$(cd "$(dirname "${1:-bin/editor}")" && pwd)/$(basename "${1:-bin/editor}")"
[ -x "$editor" ] || { echo "no editor at $editor (odin build editor -out:bin/editor)"; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/rayzr_scene_merge.XXXXXX")"
echo "repository: $work"
cp -R templates/puzzle "$work/game"
cd "$work"
git init -q -b main
git config user.email "merge-test@rayzr.invalid"
git config user.name "Merge Test"
git config merge.rayzr-scene.name "Rayzr scene merge"
git config merge.rayzr-scene.driver "'$editor' --merge-scene %O %A %B %P"
printf '*.scene.json merge=rayzr-scene\n*.component.json merge=rayzr-scene\n' > game/.gitattributes
git add -A && git commit -qm base
scene=game/scenes/title.scene.json

# set_field <file> <node name> <field path> <JSON value>
set_field() {
	python3 -I - "$@" <<-'EOF'
		import json, sys
		path, name, field, value = sys.argv[1:5]
		doc = json.load(open(path))
		def find(n):
		    if n.get("name") == name: return n
		    for c in n.get("children", []):
		        f = find(c)
		        if f: return f
		node = find(doc["root"])
		*parents, last = field.split("/")
		for p in parents: node = node.setdefault(p, {})
		node[last] = json.loads(value)
		json.dump(doc, open(path, "w"), indent=2)
	EOF
}
# get_field <file> <node name> <field path>: its JSON value
get_field() {
	python3 -I - "$@" <<-'EOF'
		import json, sys
		path, name, field = sys.argv[1:4]
		doc = json.load(open(path))
		def find(n):
		    if n.get("name") == name: return n
		    for c in n.get("children", []):
		        f = find(c)
		        if f: return f
		node = find(doc["root"])
		for p in field.split("/"): node = node[p]
		print(json.dumps(node))
	EOF
}

# 1. Different fields: clean.
git checkout -qb ours
set_field "$scene" Title properties/text '"Ours"'
git commit -qam "ours: the title's text"
git checkout -q main
git checkout -qb theirs
set_field "$scene" Title properties/fontSize 99
git commit -qam "theirs: the title's size"
git checkout -q ours
if ! git merge -q --no-edit theirs; then echo "FAIL: the clean merge conflicted"; git status --short; exit 1; fi
[ "$(get_field "$scene" Title properties/text)" = '"Ours"' ] || { echo "FAIL: ours' text lost"; exit 1; }
[ "$(get_field "$scene" Title properties/fontSize)" = '99' ] || { echo "FAIL: theirs' size lost"; exit 1; }
[ ! -e "$scene.merge.json" ] || { echo "FAIL: a sidecar after a clean merge"; exit 1; }
"$editor" --fmt --check "$scene" > /dev/null || { echo "FAIL: the merged file isn't formatted"; exit 1; }
echo "ok   different fields of a node merge cleanly"

# 2. The same field: a conflict.
git checkout -q main
git checkout -qb ours2
set_field "$scene" Title properties/text '"Mine"'
git commit -qam "ours2"
git checkout -q main
git checkout -qb theirs2
set_field "$scene" Title properties/text '"Yours"'
git commit -qam "theirs2"
git checkout -q ours2
if git merge -q --no-edit theirs2 2> merge.log; then echo "FAIL: the same field merged without a conflict"; exit 1; fi
[ "$(get_field "$scene" Title properties/text)" = '"Mine"' ] || { echo "FAIL: ours not kept"; exit 1; }
grep -q '"theirs": "\\"Yours\\""' "$scene.merge.json" || { echo "FAIL: the sidecar"; cat "$scene.merge.json"; exit 1; }
git status --short | grep -q "^UU $scene" || { echo "FAIL: git doesn't report the conflict"; git status --short; exit 1; }
grep -q "1 conflict" merge.log || { echo "FAIL: the driver's message"; cat merge.log; exit 1; }
echo "ok   the same field: a conflict, ours kept, the sidecar for the editor"
