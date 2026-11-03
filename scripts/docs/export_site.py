#!/usr/bin/env python3
"""Exports this version's documentation as a bundle for the website
(github.com/bcrowe306/rayzr_website, Astro Starlight at rayzr.app/docs).

    python3 scripts/docs/export_site.py --out build/docs_bundle \\
        [--base /docs/] [--ref main] [--version 0.1.0-dev.12]

The bundle:

    bundle.json          version, ref, commit, the sidebar (labels -> slugs)
    features.json        docs/features.json with site URLs (images/ beside it)
    pages/<slug>.md      Starlight pages (frontmatter: title, description,
                         editUrl, lastUpdated); <slug> "" is pages/index.md
    pages/_images/...    images the pages use (relative links)
    downloads/<name>.zip finished projects the pages link to: a link to a
                         folder under docs/ holding a project.json (the
                         tutorials' docs/tutorials/<name>/) becomes a zip of
                         its committed files, linked as <base>downloads/<name>.zip;
                         bundle.json lists them ("downloads") - the site
                         serves the folder at <base>downloads/

Pages come from docs/site.json: hand-written ones (docs/, engine/docs/,
editor/...) and generated ones - the node reference
(docs/generated/nodes.json, written by `editor --dump-docs`), the Lua API
(engine/definitions/engine_api.lua), the editor plugin API
(editor/definitions/editor_api.lua) and the templates (templates/*/README.md).
Links between pages become site links under --base; links to other files go
to GitHub at --ref. The website runs this script in each version's checkout,
so a version's docs are always built by that version's exporter.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REPO = "https://github.com/bcrowe306/rayzr"


# --- helpers ------------------------------------------------------------------------

def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def git(*args, default=""):
    try:
        return subprocess.check_output(["git", "-C", ROOT, *args], stderr=subprocess.DEVNULL).decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return default


def kebab(name):
    """CameraNode -> camera-node, UIXYPlotNode -> ui-xy-plot-node."""
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", name)
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1-\2", s)
    return s.lower()


def yaml_str(s):
    return json.dumps(s, ensure_ascii=False)


def split_fences(text):
    """Yields (is_code, chunk) so rewrites skip fenced code blocks."""
    out, buf, inside, fence = [], [], False, ""
    for line in text.split("\n"):
        m = re.match(r"^\s*(```+|~~~+)", line)
        if m and (not inside or m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence)):
            if not inside:
                if buf:
                    out.append((False, "\n".join(buf)))
                buf, inside, fence = [line], True, m.group(1)
            else:
                buf.append(line)
                out.append((True, "\n".join(buf)))
                buf, inside = [], False
            continue
        buf.append(line)
    if buf:
        out.append((inside, "\n".join(buf)))
    return out


def first_paragraph(text):
    """A page description: its first prose paragraph, plain text, <= 160 chars."""
    for is_code, chunk in split_fences(text):
        if is_code:
            continue
        for para in re.split(r"\n\s*\n", chunk):
            p = para.strip()
            if not p or p.startswith(("#", "|", "-", "*", ">", "<", "!", "1.")):
                continue
            p = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", p)
            p = re.sub(r"[`*_]", "", p)
            p = " ".join(p.split())
            if len(p) > 160:
                p = p[:157].rsplit(" ", 1)[0] + "..."
            return p
    return ""


class Exporter:
    def __init__(self, out, base, ref, version):
        self.out = out
        self.pages_dir = os.path.join(out, "pages")
        self.base = base if base.endswith("/") else base + "/"
        self.ref = ref
        self.version = version
        self.site = json.loads(read("docs/site.json"))
        self.file_slugs = {}  # repository path -> slug
        for sec in self.site["sections"]:
            for it in sec["items"]:
                if "file" in it:  # (generated pages may name a file too: links to it go to them)
                    self.file_slugs[it["file"]] = it["slug"]
        # Node pages (docs/nodes/<Type>.md -> the generated node page) are known
        # up front: pages before the reference in the sidebar link to them too.
        for sec in self.site["sections"]:
            for it in sec["items"]:
                if it.get("generated") == "nodes":
                    for n in json.loads(read("docs/generated/nodes.json"))["nodes"]:
                        self.file_slugs[f"docs/nodes/{n['type']}.md"] = f"{it['slug']}/{kebab(n['type'])}"
        self.images = {}  # repository path -> bundle path under pages/
        self.downloads = {}  # repository folder -> {"name", "path", "url", "source", "files"}
        self.warnings = []
        # Links to files go to GitHub: they must be committed (None: not a git checkout).
        listed = git("ls-files", default=None)
        self.tracked = set(listed.split("\n")) if listed else None
        self.tracked_dirs = {os.path.dirname(f) for f in self.tracked or ()}
        for d in list(self.tracked_dirs):
            while d:
                d = os.path.dirname(d)
                self.tracked_dirs.add(d)

    # --- links ----------------------------------------------------------------------

    def url(self, slug, anchor=""):
        u = self.base + (slug + "/" if slug else "")
        return u + ("#" + anchor if anchor else "")

    def exists(self, rel):
        """A committed file or folder (any file on disk outside a git checkout)."""
        if self.tracked is None:
            return os.path.exists(os.path.join(ROOT, rel))
        return rel in self.tracked or rel in self.tracked_dirs

    def page_path(self, slug):
        return os.path.join(self.pages_dir, (slug or "index") + ".md")

    def image_link(self, src_rel, page_slug):
        """Copies an image into the bundle; the link relative to the page."""
        if src_rel not in self.images:
            dst = "_images/" + src_rel.replace("/", "__")
            os.makedirs(os.path.join(self.pages_dir, "_images"), exist_ok=True)
            shutil.copyfile(os.path.join(ROOT, src_rel), os.path.join(self.pages_dir, dst))
            self.images[src_rel] = dst
        page_dir = os.path.dirname(slug_file(page_slug))
        return os.path.relpath(self.images[src_rel], page_dir or ".").replace(os.sep, "/")

    def project_files(self, folder):
        """The files of a project folder that go in its zip: the committed ones
        (every file outside a git checkout), hidden ones left out."""
        out = []
        for d, dirs, files in os.walk(os.path.join(ROOT, folder)):
            dirs[:] = sorted(x for x in dirs if not x.startswith("."))
            for f in sorted(files):
                rel = os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/")
                if f.startswith(".") or (self.tracked is not None and rel not in self.tracked):
                    continue
                out.append(rel)
        return out

    def download(self, folder):
        """Zips a project folder (once) into downloads/; its site URL."""
        if folder not in self.downloads:
            name = "-".join(folder.split("/")[1:]) or os.path.basename(folder)
            files = self.project_files(folder)
            if not any(f == folder + "/project.json" for f in files):
                self.warnings.append(f"{folder}: project.json isn't committed (the download would be empty)")
            dst = os.path.join(self.out, "downloads", name + ".zip")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            # (The same bytes for the same files: fixed dates, sorted names.)
            with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
                for rel in files:
                    info = zipfile.ZipInfo(f"{name}/{rel[len(folder) + 1:]}", (2020, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o644 << 16
                    with open(os.path.join(ROOT, rel), "rb") as f:
                        z.writestr(info, f.read())
            self.downloads[folder] = {"name": name, "path": f"downloads/{name}.zip",
                                      "url": f"{self.base}downloads/{name}.zip", "source": folder, "files": len(files)}
        return self.downloads[folder]["url"]

    def rewrite(self, text, rel_path, page_slug):
        """Page links -> site URLs, images -> the bundle, other files -> GitHub."""
        base_dir = os.path.dirname(rel_path)

        def resolve(target):
            path, _, anchor = target.partition("#")
            resolved = os.path.normpath(os.path.join(base_dir, path)) if path else rel_path
            return resolved, anchor

        def fix_link(m):
            bang, label, target = m.group(1), m.group(2), m.group(3)
            if re.match(r"^[a-z][a-z0-9+.-]*://|^mailto:", target):
                return m.group(0)
            if target.startswith("#") or target.startswith(("_images/", "../_images/")) or "/_images/" in target:
                return m.group(0)  # (anchors; images already in the bundle)
            resolved, anchor = resolve(target)
            full = os.path.join(ROOT, resolved)
            if bang:
                if os.path.isfile(full):
                    return f"![{label}]({self.image_link(resolved, page_slug)})"
                self.warnings.append(f"{rel_path}: missing image {target}")
                return m.group(0)
            if resolved in self.file_slugs:
                return f"[{label}]({self.url(self.file_slugs[resolved], anchor)})"
            if is_project_folder(resolved):
                return f"[{label}]({self.download(resolved)})"
            if not self.exists(resolved):
                self.warnings.append(f"{rel_path}: broken link {target}")
            kind = "tree" if os.path.isdir(full) or resolved in self.tracked_dirs else "blob"
            return f"[{label}]({REPO}/{kind}/{self.ref}/{resolved}{'#' + anchor if anchor else ''})"

        def annotated(m):
            # An image alone on its line with <image>.annotations.json beside
            # it (scripts/docs/screenshots.sh): numbered callouts over it and
            # their labels listed below (the site styles .rz-annotated).
            alt, target = m.group(1), m.group(2)
            resolved, _ = resolve(target)
            ann = os.path.join(ROOT, os.path.splitext(resolved)[0] + ".annotations.json")
            if not (os.path.isfile(os.path.join(ROOT, resolved)) and os.path.isfile(ann)):
                return m.group(0)
            with open(ann) as f:
                a = json.load(f)
            return annotated_figure(alt, self.image_link(resolved, page_slug), a)

        out = []
        for is_code, chunk in split_fences(text):
            if is_code:
                out.append(chunk)
                continue
            chunk = re.sub(r"^!\[([^\]]*)\]\(([^)\s]+)\)[ \t]*$", annotated, chunk, flags=re.M)
            # (Labels may be code: [`file.md`](file.md).)
            out.append(re.sub(r"(!?)\[([^\]]*)\]\(<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\)", fix_link, chunk))
        return "\n".join(out)

    # --- pages ----------------------------------------------------------------------

    def write_page(self, slug, title, body, source=None, description=None):
        fm = ["---", f"title: {yaml_str(title)}"]
        desc = description if description is not None else first_paragraph(body)
        if desc:
            fm.append(f"description: {yaml_str(desc)}")
        if source:
            fm.append(f"editUrl: {yaml_str(f'{REPO}/edit/main/{source}')}")
            date = git("log", "-1", "--format=%cI", "HEAD", "--", source)  # (the checkout is at --ref)
            if date:
                fm.append(f"lastUpdated: {date}")
        else:
            fm.append("editUrl: false")
        fm.append("---")
        path = self.page_path(slug)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(fm) + "\n\n" + body.strip() + "\n")

    def file_page(self, item):
        rel, slug = item["file"], item["slug"]
        text = read(rel)
        title = item.get("label")
        m = re.match(r"^\s*#\s+(.+?)\s*\n", text)
        if m:
            title = title or m.group(1).strip()
            text = text[m.end():]
        title = title or os.path.splitext(os.path.basename(rel))[0]
        text = convert_markup(text)
        self.write_page(slug, page_title(item, title), self.rewrite(text, rel, slug), source=rel)
        return {"label": item.get("label") or title, "slug": slug}

    # --- generated: templates ---------------------------------------------------------

    def templates(self, item):
        slug = item["slug"]
        root = os.path.join(ROOT, "templates")
        entries = []
        for t in sorted(os.listdir(root)):
            meta = os.path.join(root, t, "template.json")
            if os.path.isfile(meta):
                with open(meta) as f:
                    m = json.load(f)
                entries.append((m.get("order", 0), t, m))
        body = ["New Project templates are small, complete games: play one, then change it. "
                "In the editor: **Help > Welcome > New Project**. The art is from "
                "[Kenney](https://kenney.nl) (CC0: use it for anything).", ""]
        for _, t, meta in sorted(entries):
            rel = f"templates/{t}/README.md"
            text = read(rel)
            text = re.sub(r"^\s*#\s+.+\n", "", text, count=1)
            text = "\n".join("#" + l if l.startswith("#") else l for l in text.split("\n"))
            body += [f"## {meta.get('name', t)}", ""]
            if os.path.isfile(os.path.join(root, t, "preview.png")):
                body += [self.rewrite(f"![{meta.get('name', t)}](preview.png)", rel, slug), ""]
            body += [self.rewrite(convert_markup(text), rel, slug).strip(), ""]
        self.write_page(slug, "Templates", "\n".join(body), source="templates/README.md")
        return {"label": item.get("label", "Templates"), "slug": slug}

    # --- generated: nodes -------------------------------------------------------------

    def nodes(self, item):
        base = item["slug"]
        data = json.loads(read("docs/generated/nodes.json"))
        lua_classes, _, _ = parse_lua_api(os.path.join(ROOT, "engine", "definitions", "engine_api.lua"))
        extras_dir = os.path.join(ROOT, "docs", "nodes")
        categories = {}
        for n in data["nodes"]:
            categories.setdefault(n["category"], []).append(n)
            # A node page's hand-written part (docs/nodes/<Type>.md) links to
            # other nodes as `[Area](AreaNode.md)` (the editor's Node
            # Reference follows them too): those go to the generated pages.
            self.file_slugs[f"docs/nodes/{n['type']}.md"] = f"{base}/{kebab(n['type'])}"

        common_rows = props_table(data["common"])
        self.write_page(f"{base}/common", "Common properties (every node)",
                        "Every node has these Transform properties (the Inspector's Transform section). "
                        "Origin appears on nodes that draw something around a pivot.\n\n" + common_rows,
                        description="The Transform properties every node has: position, rotation, scale, origin, layer, Z index, Y-sort, pause mode.")

        index = ["Every node type, by category. A scene is a tree of nodes; add one with **Add Node** "
                 "(Ctrl+A) in the editor or `Scene.create_node(type)` from Lua.", "",
                 f"Every node also has the [common properties]({self.url(base + '/common')}).", ""]
        sidebar = [{"label": "Overview", "slug": base}, {"label": "Common properties", "slug": f"{base}/common"}]
        for cat, nodes in categories.items():
            index += [f"## {cat}", "", "| Node | |", "|---|---|"]
            group = {"label": cat, "collapsed": True, "items": []}
            for n in nodes:
                slug = f"{base}/{kebab(n['type'])}"
                index.append(f"| [{n['name']}]({self.url(slug)}) `{n['type']}` | {md_cell(n['description'])} |")
                group["items"].append({"label": n["name"], "slug": slug})
                self.node_page(slug, n, lua_classes, extras_dir, base)
            index.append("")
            sidebar.append(group)
        self.write_page(base, "Nodes", "\n".join(index),
                        description="Reference for every Rayzr node type: properties, defaults, Lua methods and examples.")
        return {"label": item.get("label", "Nodes"), "collapsed": True, "items": sidebar}

    def node_page(self, slug, n, lua_classes, extras_dir, base):
        out = [n["description"], "", f"**Type:** `{n['type']}` · **Category:** {n['category']}"]
        if n["aliases"]:
            out[-1] += " · **Also found as:** " + ", ".join(f"`{a}`" for a in n["aliases"])
        out.append("")
        extra_rel = f"docs/nodes/{n['type']}.md"
        source = None
        if os.path.isfile(os.path.join(ROOT, extra_rel)):
            out += [self.rewrite(convert_markup(read(extra_rel)), extra_rel, slug).strip(), ""]
            source = extra_rel
        out += ["## Properties", ""]
        if n["properties"]:
            out += [props_table(n["properties"]), ""]
        elif source:
            out += ["No reflected properties of its own: its settings are described above.", ""]
        else:
            out += ["No properties of its own.", ""]
        out += [f"Plus the [common properties]({self.url(base + '/common')}) every node has.", ""]
        cls = lua_classes.get(n["type"])
        if cls and cls["functions"]:
            out += ["## Lua methods", "",
                    f"Call them on the node (`self.node` in its script, or `self.node:get_node(\"path\")`). "
                    f"Every node also has the [Node methods]({self.url('reference/lua/node')}).", ""]
            out += render_functions(n["type"], cls, level="###")
        out += ["## In a scene file", "", "```json",
                json.dumps(example_scene_node(n), indent=2), "```", ""]
        self.write_page(slug, n["name"], "\n".join(out), source=source,
                        description=f"{n['name']} ({n['type']}): {n['description']}"[:160])

    # --- generated: Lua API -----------------------------------------------------------

    def lua_api(self, item):
        """The Lua API (#45): a page per module (its guide from docs/lua/<Name>.md -
        use cases and a complete example - then every function), the Node class,
        the other node classes (each with its node page) and the types."""
        base = item["slug"]
        classes, order, globals_ = parse_lua_api(os.path.join(ROOT, "engine", "definitions", "engine_api.lua"))
        modules, nodes, types = [], [], []
        for name in order:
            c = classes[name]
            if not c["functions"] and not c["fields"] and not c["doc"]:
                continue
            if name == "Node":
                continue
            if name.endswith("Node"):
                nodes.append(name)
            elif name.endswith("Module") or name in globals_:
                modules.append(name)
            else:
                types.append(name)
        modules.sort(key=lambda n: globals_.get(n, n))
        sidebar = [{"label": "Overview", "slug": base}]
        ov = ["The engine's Lua 5.4 API, generated from `engine/definitions/engine_api.lua` - the same "
              "definitions the Code tab (and any LuaLS editor) uses for completion and hover docs. "
              f"The [scripting guide]({self.url('scripting')}) explains scripts, events and the lifecycle.", ""]
        count = 0

        def guide(name, slug):
            rel = f"docs/lua/{name}.md"
            return self.rewrite(read(rel), rel, slug).strip() if os.path.exists(os.path.join(ROOT, rel)) else ""

        # (Guides link to each other: docs/lua/<Global>.md -> its module page.)
        for nm in modules:
            title = globals_.get(nm, nm)
            self.file_slugs[f"docs/lua/{title}.md"] = f"{base}/{kebab(title)}"
        self.file_slugs["docs/lua/Node.md"] = f"{base}/node"

        # Modules: a page each.
        ov += ["## Modules", "", "The global tables scripts call.", "", "| Module | |", "|---|---|"]
        mod_items = []
        for nm in modules:
            title = globals_.get(nm, nm)
            c = classes[nm]
            slug = f"{base}/{kebab(title)}"
            text = "\n".join(c["doc"]).strip()
            lines = [text, ""] if text else []
            g = guide(title, slug)
            if g:
                lines += [g, ""]
            lines += ["## Functions", ""] + render_functions(title, c)
            self.write_page(slug, f"{title} (Lua)", "\n".join(lines), description=first_paragraph(text) or f"The {title} module.")
            mod_items.append({"label": title, "slug": slug})
            ov.append(f"| [{title}]({self.url(slug)}) | {md_cell(first_paragraph(text))} |")
            count += len(c["functions"])
        sidebar.append({"label": "Modules", "collapsed": True, "items": mod_items})

        # Node: the methods every node has.
        node = classes.get("Node")
        if node:
            slug = f"{base}/node"
            lines = ["\n".join(node["doc"]).strip(), ""]
            g = guide("Node", slug)
            if g:
                lines += [g, ""]
            lines += render_class("Node", node)[2:]
            self.write_page(slug, "Node (Lua)", "\n".join(lines), description="The methods and fields every node has.")
            sidebar.append({"label": "Node", "slug": slug})
            ov += ["", "## Nodes", "", f"[Node]({self.url(slug)}): what every node has. Each node type adds its own "
                   "methods, listed on its page with the rest of that node's reference:", ""]
            count += len(node["functions"])

        # The node types: their own methods (also on their node pages).
        slug = f"{base}/nodes"
        lines = ["Every node type's own methods (on `self.node` or any node of that type), with a link to its "
                 "node page. Properties are fields too: `node.position = Vec2(10, 20)`.", ""]
        for nm in nodes:
            npage = self.url(f"reference/nodes/{kebab(nm)}") if self.exists(f"docs/nodes/{nm}.md") else ""
            lines += render_class(nm, classes[nm], None, npage)
            count += len(classes[nm]["functions"])
        self.write_page(slug, "Lua API: node types", "\n".join(lines), description="Each node type's Lua methods.")
        sidebar.append({"label": "Node types", "slug": slug})
        ov.append(f"- [Every node type's methods]({self.url(slug)})")

        # Types.
        slug = f"{base}/types"
        lines = ["Values passed around: vectors, hits, events, options tables.", ""]
        for nm in types:
            lines += render_class(nm, classes[nm], globals_.get(nm))
            count += len(classes[nm]["functions"])
        self.write_page(slug, "Lua API: types", "\n".join(lines), description="Values passed around: vectors, hits, events, options tables.")
        sidebar.append({"label": "Types", "slug": slug})
        ov += ["", "## Types", "", f"[Values passed around]({self.url(slug)}): vectors, hits, events, options tables.",
               "", f"{count} functions in {len(modules) + len(nodes) + len(types) + 1} classes and modules."]
        self.write_page(base, "Lua API", "\n".join(ov),
                        description="Reference for Rayzr's Lua 5.4 scripting API: modules, nodes and types, with examples.")
        return {"label": item.get("label", "Lua API"), "collapsed": True, "items": sidebar}

    def plugin_api(self, item):
        slug = item["slug"]
        classes, order, _ = parse_lua_api(os.path.join(ROOT, "editor", "definitions", "editor_api.lua"))
        lines = ["The `Editor`, `ui` and overlay APIs editor plugins use "
                 f"(the [plugins guide]({self.url(self.file_slugs.get('editor/docs/plugin_guide.md', 'editor/plugins'))})). "
                 "Generated from `editor/definitions/editor_api.lua`.", ""]
        for n in order:
            c = classes[n]
            if c["functions"] or c["fields"]:
                lines += render_class(n, c, {"EditorAPI": "Editor", "EditorUI": "ui"}.get(n))
        self.write_page(slug, "Editor plugin API", "\n".join(lines),
                        description="Reference for the Lua API of Rayzr editor plugins: commands, panels, events, inspectors.")
        return {"label": item.get("label", "Editor plugin API"), "slug": slug}

    # --- the website's features (docs/features.json) -----------------------------------

    def features(self):
        """features.json + its images (bundle/images/) for the site's features
        section; docs links become site URLs."""
        path = os.path.join(ROOT, "docs", "features.json")
        if not os.path.isfile(path):
            return
        with open(path) as f:
            data = json.load(f)
        data.pop("$comment", None)
        os.makedirs(os.path.join(self.out, "images"), exist_ok=True)
        for feat in data["features"]:
            if feat.get("docs") is not None:
                slug, _, anchor = feat["docs"].partition("#")
                feat["url"] = self.url(slug, anchor)
            if feat.get("image"):
                name = os.path.basename(feat["image"])
                shutil.copyfile(os.path.join(ROOT, "docs", feat["image"]), os.path.join(self.out, "images", name))
                feat["image"] = "images/" + name
        with open(os.path.join(self.out, "features.json"), "w") as f:
            json.dump(data, f, indent=2)

    # --- run --------------------------------------------------------------------------

    def run(self):
        if os.path.isdir(self.out):
            shutil.rmtree(self.out)
        os.makedirs(self.pages_dir)
        sidebar = []
        for sec in self.site["sections"]:
            group = {"label": sec["label"], "items": []}
            for it in sec["items"]:
                if "generated" not in it:
                    group["items"].append(self.file_page(it))
                else:
                    gen = {"templates": self.templates, "nodes": self.nodes,
                           "lua-api": self.lua_api, "plugin-api": self.plugin_api}[it["generated"]]
                    group["items"].append(gen(it))
            sidebar.append(group)
        self.features()
        bundle = {
            "schema": 1,
            "version": self.version,
            "ref": self.ref,
            "commit": git("rev-parse", "HEAD"),
            "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
            "base": self.base,
            "sidebar": sidebar,
            "downloads": sorted(self.downloads.values(), key=lambda d: d["name"]),
        }
        with open(os.path.join(self.out, "bundle.json"), "w") as f:
            json.dump(bundle, f, indent=2)
        n = sum(1 for _, _, fs in os.walk(self.pages_dir) for x in fs if x.endswith(".md"))
        print(f"{self.out}: {n} pages, {len(self.images)} images, {len(self.downloads)} downloads ({self.version or 'unversioned'})")
        for w in self.warnings:
            print("warning:", w, file=sys.stderr)
        return n


def html_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def annotated_figure(alt, src, a):
    """The markdown + HTML of an annotated screenshot (positions in % of the
    image, so the callouts follow it at any width)."""
    W, H = float(a["width"]), float(a["height"])
    marks, items = [], []
    for i, c in enumerate(a["callouts"], 1):
        x, y = max(c["x"], 0) / W * 100, max(c["y"], 0) / H * 100
        w = min(c["w"], W - max(c["x"], 0)) / W * 100
        h = min(c["h"], H - max(c["y"], 0)) / H * 100
        marks.append(f'<div class="rz-callout" style="left:{x:.2f}%;top:{y:.2f}%;width:{w:.2f}%;height:{h:.2f}%" '
                     f'title="{html_escape(c["label"])}"><span class="rz-callout__n">{i}</span></div>')
        items.append(f"<li>{html_escape(c['label'])}</li>")
    return "\n".join([
        '<figure class="rz-annotated">', '<div class="rz-annotated__frame">', "",
        f"![{alt}]({src})", "",
        *marks, "</div>",
        f'<figcaption><ol class="rz-annotated__legend">{"".join(items)}</ol></figcaption>',
        "</figure>"])


def is_project_folder(rel):
    """A Rayzr project kept with the docs (docs/tutorials/<name>/): links to
    it become a download of the folder as a zip."""
    return rel.startswith("docs/") and os.path.isfile(os.path.join(ROOT, rel, "project.json"))


def slug_file(slug):
    return (slug or "index") + ".md"


def page_title(item, title):
    return item.get("title") or title


def md_cell(s):
    return s.replace("|", "\\|").replace("\n", " ")


def convert_markup(text):
    """GitHub / MkDocs bits Starlight doesn't read: attribute lists."""
    out = []
    for is_code, chunk in split_fences(text):
        if not is_code:
            chunk = re.sub(r"\{\s*width=\"?\d+\"?\s*\}", "", chunk)
        out.append(chunk)
    return "\n".join(out)


def fmt_default(p):
    v = p["default"]
    if p["kind"] == "string":
        return f"`\"{v}\"`" if v else "`\"\"`"
    if p["kind"] == "flags":
        return "`[" + ", ".join(v) + "]`" if v else "`[]`"
    if isinstance(v, bool):
        return f"`{str(v).lower()}`"
    if isinstance(v, list):
        return "`(" + ", ".join(str(x) for x in v) + ")`"
    return f"`{v}`"


def props_table(props):
    rows = ["| Property | Type | Default | Description |", "|---|---|---|---|"]
    for p in props:
        kind = p["kind"]
        if p.get("values"):
            vals = p["values"]
            kind += ": " + ", ".join(f"`{v}`" for v in vals[:12]) + (" ..." if len(vals) > 12 else "")
        doc = p["doc"]
        if "min" in p:
            doc += f" Range {p['min']:g} to {p['max']:g}."
        if p.get("runtime"):
            doc += " *Runtime state: read-only, not saved.*"
        rows.append(f"| `{p['name']}` | {md_cell(kind)} | {fmt_default(p)} | {md_cell(doc)} |")
    return "\n".join(rows)


def example_scene_node(n):
    props = {}
    for p in n["properties"]:
        if p.get("runtime") or "." in p["name"]:
            continue
        props[p["name"]] = p["default"]
        if len(props) == 3:
            break
    node = {"type": n["type"], "name": n["name"].replace(" ", ""), "position": [0, 0]}
    if props:
        node["properties"] = props
    return node


# --- Lua API parsing (LuaCATS definitions) ---------------------------------------------

def split_type(rest):
    """'<type> <description>' -> (type, description): a type ends at the first
    space outside {}, (), [] and <> (table and function types have spaces)."""
    depth = 0
    for i, ch in enumerate(rest):
        if ch in "{([<":
            depth += 1
        elif ch in "})]>":
            depth -= 1
        elif ch.isspace() and depth == 0:
            return rest[:i], rest[i:].strip()
    return rest, ""


def parse_lua_api(path):
    """LuaCATS definitions -> classes: {name: {doc, fields, functions, parents}}."""
    classes, order, table_of = {}, [], {}
    doc, params, returns = [], [], []
    deprecated = False
    current = None
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for line in lines:
        s = line.strip()
        m = re.match(r"^---@class\s+([\w.]+)\s*(?::\s*(.+))?", s)
        if m:
            name = m.group(1)
            if name not in classes:
                classes[name] = {"doc": [], "fields": [], "functions": [], "parents": (m.group(2) or "").strip()}
                order.append(name)
            current = name
            classes[name]["doc"] += doc
            doc, params, returns = [], [], []
            continue
        m = re.match(r"^---@field\s+(\S+)\s+(.*)", s)
        if m and current:
            classes[current]["fields"].append((m.group(1), *split_type(m.group(2))))
            continue
        m = re.match(r"^---@param\s+(\S+)\s+(.*)", s)
        if m:
            params.append((m.group(1), *split_type(m.group(2))))
            continue
        m = re.match(r"^---@return\s+(.*)", s)
        if m:
            returns.append(split_type(m.group(1)))
            continue
        if s.startswith("---@deprecated"):
            deprecated = True  # an old name kept until 2.0 (#327)
            continue
        if s.startswith("---@"):
            continue
        if s.startswith("---"):
            doc.append(s[3:].rstrip())
            continue
        m = re.match(r"^local\s+(\w+)\s*=\s*\{\}", s)
        if m and current:
            table_of[m.group(1)] = current
            if doc and not classes[current]["doc"]:
                classes[current]["doc"] = doc
            doc = []
            continue
        m = re.match(r"^function\s+(\w+)([.:])(\w+)\s*\(([^)]*)\)", s)
        if m:
            owner = table_of.get(m.group(1), m.group(1))
            if owner not in classes:
                classes[owner] = {"doc": [], "fields": [], "functions": [], "parents": ""}
                order.append(owner)
            classes[owner]["functions"].append({
                "name": m.group(3), "sep": m.group(2), "args": m.group(4), "doc": doc,
                "params": params, "returns": returns, "deprecated": deprecated})
            doc, params, returns, deprecated = [], [], [], False
            continue
        if s == "" or not s.startswith("--"):
            doc, params, returns, deprecated = [], [], [], False
    globals_ = {}
    for line in lines:
        m = re.match(r"^(\w+)\s*=\s*(\w+)\s*$", line.strip())
        if m and m.group(2) in classes:
            globals_[m.group(2)] = m.group(1)
    return classes, order, globals_


def doc_body(lines):
    """A function's doc lines; `Example: \\`code\\`` becomes a Lua code block."""
    out = []
    for l in lines:
        m = re.match(r"^\s*Example:\s*`(.+)`\s*$", l)
        if m:
            out += ["", "```lua", m.group(1), "```"]
        else:
            out.append(l)
    return "\n".join(out).strip()


def render_functions(title, c, level="###"):
    """Each function: its signature, description and example, then its
    parameters and returns as tables (#45)."""
    out = []
    for fn in c["functions"]:
        out += [f"{level} {title}{fn['sep']}{fn['name']}({fn['args']})", ""]
        body = doc_body(fn["doc"])
        if body:
            out += [body, ""]
        if fn["params"]:
            out += ["| Parameter | Type | |", "|---|---|---|"]
            for p, t, d in fn["params"]:
                out.append(f"| `{p}` | `{md_cell(t)}` | {md_cell(d)} |")
            out.append("")
        if fn["returns"]:
            out += ["| Returns | |", "|---|---|"]
            for t, d in fn["returns"]:
                out.append(f"| `{md_cell(t)}` | {md_cell(d or '')} |")
            out.append("")
    return out


def render_class(name, c, global_name=None, node_page=""):
    title = global_name or name
    out = [f"## {title}", ""]
    if node_page:
        out += [f"*Node reference: [{name}]({node_page})*", ""]
    if c["parents"]:
        out += [f"*Inherits {c['parents']}*", ""]
    text = "\n".join(c["doc"]).strip()
    if text:
        out += [text, ""]
    if c["fields"]:
        out += ["| Field | Type | |", "|---|---|---|"]
        for f, t, d in c["fields"]:
            out.append(f"| `{f}` | `{md_cell(t)}` | {md_cell(d)} |")
        out.append("")
    out += render_functions(title, c)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "docs_bundle"))
    ap.add_argument("--base", default="/docs/", help="the site path the pages live under")
    ap.add_argument("--ref", default="main", help="git ref for GitHub links (a tag or main)")
    ap.add_argument("--version", default="", help="the version these docs are for")
    a = ap.parse_args(argv)
    Exporter(os.path.abspath(a.out), a.base, a.ref, a.version).run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
