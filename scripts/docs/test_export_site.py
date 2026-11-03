#!/usr/bin/env python3
"""Tests for export_site.py (the website's docs bundle) and check_docs.py:
    python3 scripts/docs/test_export_site.py
Helpers (slugs, fences, descriptions, annotated figures, Lua docs), a full
export of this checkout (every page has a title, links point at site URLs or
GitHub, images are copied, tutorial projects are zipped), and the checks
passing on it (a missing image fails them).
"""
import json
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_docs  # noqa: E402
import export_site as x  # noqa: E402


class Helpers(unittest.TestCase):
    def test_kebab(self):
        self.assertEqual(x.kebab("CameraNode"), "camera-node")
        self.assertEqual(x.kebab("UIXYPlotNode"), "uixy-plot-node")
        self.assertEqual(x.kebab("Node"), "node")
        self.assertEqual(x.kebab("LdtkLevelNode"), "ldtk-level-node")

    def test_fences(self):
        parts = x.split_fences("a\n```lua\n[x](y)\n```\nb")
        self.assertEqual([c for c, _ in parts], [False, True, False])
        self.assertIn("[x](y)", parts[1][1])

    def test_first_paragraph(self):
        self.assertEqual(x.first_paragraph("# T\n\n| a |\n\nThe **first** [real](x.md) one.\n\nMore."), "The first real one.")
        self.assertTrue(len(x.first_paragraph("word " * 100)) <= 160)

    def test_doc_body_examples(self):
        body = x.doc_body(["Does a thing.", "", "Example: `node:do(1)`"])
        self.assertIn("```lua\nnode:do(1)\n```", body)

    def test_annotated_figure(self):
        html = x.annotated_figure("Alt", "../_images/a.png", {"width": 200, "height": 100, "callouts": [
            {"label": "Panel <one>", "x": 20, "y": 10, "w": 100, "h": 50},
            {"label": "Off the edge", "x": -5, "y": 90, "w": 300, "h": 30}]})
        self.assertIn('left:10.00%;top:10.00%;width:50.00%;height:50.00%', html)
        self.assertIn("Panel &lt;one&gt;", html)
        self.assertNotIn("<one>", html)
        # (Clamped to the image.)
        self.assertIn('left:0.00%;top:90.00%;width:100.00%;height:10.00%', html)
        self.assertIn("![Alt](../_images/a.png)", html)
        self.assertEqual(html.count("<li>"), 2)

    def test_fmt_default(self):
        self.assertEqual(x.fmt_default({"kind": "boolean", "default": True}), "`true`")
        self.assertEqual(x.fmt_default({"kind": "vec2", "default": [1, 2]}), "`(1, 2)`")
        self.assertEqual(x.fmt_default({"kind": "string", "default": ""}), '`""`')
        self.assertEqual(x.fmt_default({"kind": "flags", "default": ["A", "B"]}), "`[A, B]`")


class Export(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.ex = x.Exporter(os.path.join(cls.tmp, "b"), "/docs/v9.9.9/", "v9.9.9", "9.9.9")
        cls.pages = cls.ex.run()
        cls.out = os.path.join(cls.tmp, "b")
        with open(os.path.join(cls.out, "bundle.json")) as f:
            cls.bundle = json.load(f)

    def read(self, slug):
        with open(os.path.join(self.out, "pages", (slug or "index") + ".md")) as f:
            return f.read()

    def test_bundle(self):
        self.assertEqual(self.bundle["version"], "9.9.9")
        self.assertEqual(self.bundle["base"], "/docs/v9.9.9/")
        labels = [s["label"] for s in self.bundle["sidebar"]]
        self.assertEqual(labels[:3], ["Start here", "Tutorials", "Editor"])
        self.assertGreater(self.pages, 90)
        self.assertEqual(self.ex.warnings, [])

    def test_every_sidebar_page_exists_with_a_title(self):
        def walk(items):
            for it in items:
                if "items" in it:
                    yield from walk(it["items"])
                else:
                    yield it["slug"]
        for slug in walk(self.bundle["sidebar"]):
            text = self.read(slug)
            self.assertTrue(text.startswith("---\ntitle: "), slug)

    def test_links(self):
        tour = self.read("editor/tour")
        self.assertIn("](/docs/v9.9.9/editor/manual/)", tour)
        self.assertIn('class="rz-annotated"', tour)
        self.assertIn("](../_images/docs__images__editor_overview.png)", tour)
        self.assertTrue(os.path.isfile(os.path.join(self.out, "pages", "_images", "docs__images__editor_overview.png")))
        # Files that aren't pages go to GitHub at the ref.
        scripting = self.read("scripting")
        self.assertRegex(scripting, r"\]\(https://github\.com/bcrowe306/rayzr/blob/v9\.9\.9/engine/[\w/]+\.odin")
        # No relative .md links left outside code.
        for slug in ("", "scripting", "guides", "editor/manual"):
            prose = "".join(c for code, c in x.split_fences(self.read(slug)) if not code)
            self.assertIsNone(re.search(r"\]\((?!https?:|/|#|mailto:|\.\./_images|_images)[^)]*\.md", prose), slug)

    def test_generated_reference(self):
        cam = self.read("reference/nodes/camera-node")
        self.assertIn("## Properties", cam)
        self.assertIn("| `isCurrent` | boolean | `true` |", cam)
        self.assertIn("## Lua methods", cam)
        self.assertIn('"type": "CameraNode"', cam)
        lua = self.read("reference/lua/nodes")
        self.assertIn("```lua", lua)
        timer = self.read("reference/nodes/timer-node")
        self.assertIn("Plus the [common properties](/docs/v9.9.9/reference/nodes/common/)", timer)
        self.assertIn("| Auto Start | `auto_start` |", timer)  # (docs/nodes/TimerNode.md)
        self.assertIn('editUrl: "https://github.com/bcrowe306/rayzr/edit/main/docs/nodes/TimerNode.md"', timer)

    def test_frontmatter(self):
        text = self.read("getting-started/installation")
        self.assertIn('editUrl: "https://github.com/bcrowe306/rayzr/edit/main/docs/getting-started/installation.md"', text)
        self.assertIn('editUrl: false', self.read("reference/lua"))

    def test_tutorial_downloads(self):
        # A link to a project folder under docs/ (a tutorial's finished
        # project) becomes a zip in downloads/, linked under the base.
        import zipfile
        names = {d["name"]: d for d in self.bundle["downloads"]}
        for name, folder, slug in (("tutorials-scripting", "docs/tutorials/scripting", "tutorials/scripting"),
                                   ("tutorials-physics", "docs/tutorials/physics", "tutorials/physics")):
            d = names[name]
            self.assertEqual(d["source"], folder)
            self.assertEqual(d["url"], f"/docs/v9.9.9/downloads/{name}.zip")
            path = os.path.join(self.out, d["path"])
            self.assertTrue(os.path.isfile(path), path)
            with zipfile.ZipFile(path) as z:
                files = z.namelist()
            self.assertIn(f"{name}/project.json", files)
            self.assertIn(f"{name}/scenes/main.scene.json", files)
            self.assertTrue(any(f.startswith(f"{name}/scripts/") and f.endswith(".lua") for f in files))
            self.assertFalse(any(f.endswith(".md") for f in files))  # (the page itself isn't in it)
            self.assertIn(f"]({d['url']})", self.read(slug))

    def test_download_is_reproducible(self):
        a = os.path.join(self.out, "downloads", "tutorials-scripting.zip")
        ex = x.Exporter(os.path.join(self.tmp, "again"), "/docs/v9.9.9/", "v9.9.9", "9.9.9")
        ex.download("docs/tutorials/scripting")
        with open(a, "rb") as f1, open(os.path.join(self.tmp, "again", "downloads", "tutorials-scripting.zip"), "rb") as f2:
            self.assertEqual(f1.read(), f2.read())

    def test_features(self):
        with open(os.path.join(self.out, "features.json")) as f:
            feats = json.load(f)
        self.assertNotIn("$comment", feats)
        for ft in feats["features"]:
            if "docs" in ft:
                self.assertTrue(ft["url"].startswith("/docs/v9.9.9/"), ft["url"])
            if ft.get("image"):
                self.assertTrue(os.path.isfile(os.path.join(self.out, ft["image"])))


class Checks(unittest.TestCase):
    def test_missing_image_fails(self):
        # A page showing an image that isn't there is an error (a tutorial's
        # screenshot its drive didn't take, a typo).
        with tempfile.TemporaryDirectory() as tmp:
            ex = x.Exporter(os.path.join(tmp, "b"), "/docs/", "main", "t")
            os.makedirs(ex.pages_dir)
            ex.rewrite("Text.\n\n![Step 2](../images/tutorial-nothing_here.png)\n", "docs/tutorials/scripting.md", "tutorials/scripting")
            self.assertEqual(ex.warnings, ["docs/tutorials/scripting.md: missing image ../images/tutorial-nothing_here.png"])
            ex.warnings.clear()
            ex.rewrite("![Fine](../images/tutorial-scripting_console.png)", "docs/tutorials/scripting.md", "tutorials/scripting")
            self.assertEqual(ex.warnings, [])

    def test_this_checkout_passes(self):
        c = check_docs.Checker()
        c.nodes(None)
        site, slugs = c.site()
        c.links()
        c.lua(site)
        c.features(slugs)
        self.assertEqual(c.errors, [])


if __name__ == "__main__":
    unittest.main()
