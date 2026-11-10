#!/usr/bin/env bash
# Checks the Lua of the New Project templates (templates/), the tutorials'
# finished projects (docs/tutorials/*/) and the demo project with
# lua-language-server, as the Code tab sees them: each project is copied,
# the editor writes its Lua tooling files into the copy (--lua-setup: the
# engine API definitions, the generated project_types.lua, .luarc.json with
# the project's Lua Checks preset), then `lua-language-server --check` runs
# over it. Any warning or error - in a script or in the definitions - fails
# (#403: they had false warnings; this keeps them at none).
#   scripts/luals_check.sh                      # everything
#   scripts/luals_check.sh templates/platformer # some projects
#   LEVEL=Information scripts/luals_check.sh    # information too (default Warning)
# Needs bin/editor (EDITOR_BIN) and lua-language-server (LUALS; default
# lua-language-server/bin/lua-language-server: scripts/ci/fetch_luals.sh).
set -uo pipefail
cd "$(dirname "$0")/.."

editor="${EDITOR_BIN:-bin/editor}"
[ -x "$editor" ] || [ -x "$editor.exe" ] || { echo "no editor at $editor (odin build editor \$(scripts/odin_flags.sh) -out:bin/editor)" >&2; exit 2; }
luals="${LUALS:-lua-language-server/bin/lua-language-server}"
[ -x "$luals" ] || [ -x "$luals.exe" ] || { echo "no lua-language-server at $luals (scripts/ci/fetch_luals.sh)" >&2; exit 2; }
luals="$(cd "$(dirname "$luals")" && pwd)/$(basename "$luals")" # (run from inside each copy)
level="${LEVEL:-Warning}"

projects=("$@")
if [ ${#projects[@]} -eq 0 ]; then
	for d in templates/*/ docs/tutorials/*/; do [ -f "$d/project.json" ] && projects+=("${d%/}"); done
	projects+=(assets/demo_project)
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/rayzr_luals.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
failed=0
total=0
for p in "${projects[@]}"; do
	name="$(echo "$p" | tr '/' '_')"
	copy="$tmp/$name"
	cp -R "$p" "$copy"
	# Only what the editor writes: not a stale copy from someone's editor.
	rm -rf "$copy/.rayzr" "$copy/.luarc.json"
	if ! "$editor" --lua-setup "$copy" > "$tmp/$name.setup.log" 2>&1; then
		echo "FAIL  $p: the editor's --lua-setup failed:"
		sed 's/^/      /' "$tmp/$name.setup.log"
		failed=$((failed + 1))
		continue
	fi
	(cd "$copy" && "$luals" --check=. --checklevel="$level" --check_format=json --check_out_path="$tmp/$name.json" --logpath="$tmp/log" --metapath="$tmp/meta" > "$tmp/$name.check.log" 2>&1)
	# (No problems: no file, or [] - an empty object in Lua's JSON.)
	n=$(python3 -I - "$tmp/$name.json" "$copy" <<-'EOF'
		import json, os, sys
		from urllib.parse import unquote
		path, root = sys.argv[1], os.path.realpath(sys.argv[2])
		try:
		    data = json.load(open(path))
		except (OSError, ValueError):
		    data = {}
		if not isinstance(data, dict):
		    data = {}
		count = 0
		for uri, diags in sorted(data.items()):
		    file = os.path.realpath(unquote(uri[len("file://"):]))
		    rel = os.path.relpath(file, root)
		    for d in sorted(diags, key=lambda d: d["range"]["start"]["line"]):
		        line = d["range"]["start"]["line"] + 1
		        msg = d["message"].split("\n")[0]
		        print(f"      {rel}:{line}: [{d.get('code', '')}] {msg}", file=sys.stderr)
		        count += 1
		print(count)
	EOF
	)
	total=$((total + ${n:-0}))
	if [ "${n:-0}" -gt 0 ]; then
		echo "FAIL  $p: $n problem(s) at $level or worse (above)"
		failed=$((failed + 1))
	else
		echo "ok    $p"
	fi
done
echo
if [ "$failed" -gt 0 ]; then
	echo "$failed of ${#projects[@]} projects have lua-language-server problems ($total in all)."
	echo "A false warning: fix its cause (engine/definitions/engine_api.lua, editor/lua_project_types.odin, the .luarc.json presets in editor/lua_project.odin);"
	echo "a real one: fix the script (templates come from scripts/templates/make_templates.py)."
	exit 1
fi
echo "lua-language-server: no problems in ${#projects[@]} projects."
