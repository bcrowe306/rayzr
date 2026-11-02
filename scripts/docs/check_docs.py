#!/usr/bin/env python3
"""Checks that the documentation is complete and in step with the code
(CI runs it on every push and pull request; docs/contributing/docs.md).

    python3 scripts/docs/check_docs.py [--editor bin/editor]

Fails when:
  - docs/generated/nodes.json is stale (with --editor: regenerated with
    `editor --dump-docs` and compared), or a node type has no Add Node
    description, or a property has no help line;
  - a guide (engine/docs/*.md, editor/docs/*.md, docs/**/*.md) isn't in
    docs/site.json (or its "exclude"), or site.json names a missing file;
  - docs/nodes/<Type>.md is for a type that doesn't exist;
  - a page links to a missing file or image (the exporter's warnings);
  - an engine Lua API function has no description, or more functions lack
    an `Example:` than docs/site.json's "baseline" allows (it only goes down);
  - docs/features.json links to a page that isn't in site.json.
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_site  # noqa: E402

ROOT = export_site.ROOT


class Checker:
    def __init__(self):
        self.errors = []
        self.notes = []

    def error(self, msg):
        self.errors.append(msg)

    def note(self, msg):
        self.notes.append(msg)

    # --- the node reference ------------------------------------------------------------

    def nodes(self, editor):
        path = os.path.join(ROOT, "docs", "generated", "nodes.json")
        if not os.path.isfile(path):
            self.error("docs/generated/nodes.json is missing: run `task docs:nodes`")
            return
        with open(path) as f:
            committed = f.read()
        data = json.loads(committed)
        if editor:
            with tempfile.TemporaryDirectory() as tmp:
                out = os.path.join(tmp, "nodes.json")
                r = subprocess.run([editor, "--dump-docs", out], capture_output=True, text=True)
                if r.returncode != 0 or not os.path.isfile(out):
                    self.error(f"`{editor} --dump-docs` failed ({r.returncode}): {r.stderr.strip()}")
                else:
                    with open(out) as f:
                        fresh = f.read()
                    if fresh != committed:
                        self.error("docs/generated/nodes.json is out of date: run `task docs:nodes` and commit it")
                        import difflib  # what differs (a hand-edited file can be fixed from the log)
                        diff = difflib.unified_diff(committed.splitlines(), fresh.splitlines(), "committed", "generated", lineterm="", n=1)
                        for line in list(diff)[:80]:
                            print("    " + line)
        else:
            self.note("nodes.json freshness not checked (no --editor)")
        for n in data["nodes"]:
            if not n["description"].strip():
                self.error(f"node {n['type']}: no description (editor/add_node_dialog.odin NODE_CATALOG)")
            for p in n["properties"]:
                if not p["doc"].strip():
                    self.error(f"node {n['type']}: property {p['name']} has no help (engine/property_docs.odin)")
        types = {n["type"] for n in data["nodes"]}
        for f in glob.glob(os.path.join(ROOT, "docs", "nodes", "*.md")):
            t = os.path.splitext(os.path.basename(f))[0]
            if t not in types:
                self.error(f"docs/nodes/{t}.md: no node type {t}")
        return data

    # --- the navigation ----------------------------------------------------------------

    def site(self):
        with open(os.path.join(ROOT, "docs", "site.json")) as f:
            site = json.load(f)
        listed, slugs = set(), set()
        for sec in site["sections"]:
            for it in sec["items"]:
                slugs.add(it["slug"])
                if "file" in it:
                    listed.add(it["file"])
                    if not os.path.isfile(os.path.join(ROOT, it["file"])):
                        self.error(f"docs/site.json: {it['file']} doesn't exist")
        excluded = set(site.get("exclude", []))
        guides = set()
        for pattern in ("engine/docs/*.md", "editor/docs/*.md", "docs/*.md", "docs/*/*.md"):
            for f in glob.glob(os.path.join(ROOT, pattern)):
                rel = os.path.relpath(f, ROOT).replace(os.sep, "/")
                if rel.startswith("docs/nodes/") or rel.startswith("docs/lua/"):
                    continue  # (parts of the generated node / Lua API pages)
                guides.add(rel)
        for g in sorted(guides - listed - excluded):
            self.error(f"{g} isn't in docs/site.json: add it to a section (or to \"exclude\")")
        return site, slugs

    # --- links (the exporter's warnings) -------------------------------------------------

    def links(self):
        with tempfile.TemporaryDirectory() as tmp:
            ex = export_site.Exporter(os.path.join(tmp, "bundle"), "/docs/", "main", "check")
            import contextlib
            import io
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                pages = ex.run()
            for w in ex.warnings:
                self.error(w)
            self.note(f"{pages} pages exported")

    # --- the Lua API -------------------------------------------------------------------

    def lua(self, site):
        classes, _, globals_ = export_site.parse_lua_api(os.path.join(ROOT, "engine", "definitions", "engine_api.lua"))
        no_example = no_param_doc = no_return_doc = 0
        for cname, c in classes.items():
            for fn in c["functions"]:
                if fn.get("deprecated"):
                    continue  # an old name pointing at its replacement (#327)
                doc = " ".join(fn["doc"]).strip()
                if not doc:
                    self.error(f"engine_api.lua: {cname}{fn['sep']}{fn['name']} has no description")
                if "Example:" not in doc:
                    no_example += 1
                no_param_doc += sum(1 for _, _, d in fn["params"] if not d.strip())
                no_return_doc += sum(1 for _, d in fn["returns"] if not (d or "").strip())
        # Each module has its guide (docs/lua/<Global>.md: use cases, a complete example - #45).
        no_guide = sum(1 for name, g in globals_.items()
                       if name.endswith("Module") and not os.path.exists(os.path.join(ROOT, "docs", "lua", f"{g}.md")))
        pclasses, _, _ = export_site.parse_lua_api(os.path.join(ROOT, "editor", "definitions", "editor_api.lua"))
        p_nodoc = sum(1 for c in pclasses.values() for fn in c["functions"] if not " ".join(fn["doc"]).strip())
        base = site.get("baseline", {})
        for key, value, what in (("lua_missing_examples", no_example, "engine Lua functions without an Example:"),
                                 ("lua_params_undescribed", no_param_doc, "engine Lua parameters without a description"),
                                 ("lua_returns_undescribed", no_return_doc, "engine Lua return values without a description"),
                                 ("lua_modules_without_guide", no_guide, "Lua modules without a docs/lua/<Module>.md guide"),
                                 ("plugin_missing_descriptions", p_nodoc, "editor plugin API functions without a description")):
            limit = base.get(key)
            if limit is None:
                self.note(f"{value} {what} (no baseline)")
            elif value > limit:
                self.error(f"{value} {what} - more than the baseline {limit}: document the new ones")
            elif value < limit:
                self.note(f"{value} {what} (baseline {limit}: lower it in docs/site.json)")
            else:
                self.note(f"{value} {what} (baseline {limit})")

    # --- the website's features --------------------------------------------------------

    def features(self, slugs):
        path = os.path.join(ROOT, "docs", "features.json")
        if not os.path.isfile(path):
            self.error("docs/features.json is missing")
            return
        with open(path) as f:
            data = json.load(f)
        for i, feat in enumerate(data["features"]):
            for key in ("title", "description", "icon"):
                if not feat.get(key):
                    self.error(f"docs/features.json: feature {i} has no {key}")
            doc = feat.get("docs")
            if doc is not None and doc.split("#")[0] not in slugs and not doc.startswith("reference/nodes/"):
                self.error(f"docs/features.json: {feat.get('title')}: no page {doc!r} in docs/site.json")
            img = feat.get("image")
            if img and not os.path.isfile(os.path.join(ROOT, "docs", img)):
                self.error(f"docs/features.json: {feat.get('title')}: missing image docs/{img}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Checks the documentation (see the module docstring).")
    ap.add_argument("--editor", help="the editor binary: regenerate nodes.json and compare")
    a = ap.parse_args(argv)
    c = Checker()
    c.nodes(a.editor)
    site, slugs = c.site()
    c.links()
    c.lua(site)
    c.features(slugs)
    for n in c.notes:
        print("  " + n)
    for e in c.errors:
        print("error: " + e)
    print(f"docs: {len(c.errors)} error(s)")
    return 1 if c.errors else 0


if __name__ == "__main__":
    sys.exit(main())
