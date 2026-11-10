#!/usr/bin/env python3
"""Builds the registry fixture (tests/drive/registry.drive, editor/registry_test.odin):
zips of a small plugin and template, a zip that writes outside its folder, a
screenshot, and index.json with their SHA-256s. Run it after changing them:
    python3 -I tests/drive/fixtures/registry/make_fixture.py
"""
import hashlib, json, os, struct, sys, zipfile, zlib

HERE = os.path.dirname(os.path.abspath(__file__))

PLUGIN_JSON = {"name": "Registry Hello ZZ", "version": "1.0.0",
               "description": "A plugin installed from the registry fixture.", "main": "main.lua"}
PLUGIN_V2 = dict(PLUGIN_JSON, version="1.1.0")
MAIN_LUA = 'function on_load()\n    print("hello from the registry " .. Editor.plugin.version)\nend\n'
README = "# Registry Hello ZZ\n\nA **test** plugin from the registry fixture.\n\n- prints a line when it loads\n"
TEMPLATE_JSON = {"name": "Registry Blank ZZ", "description": "A template installed from the registry fixture.",
                 "icon": "map", "order": 50}
PROJECT_JSON = {"name": "Blank", "initial_scene": "scenes/main.scene.json", "scenes": ["scenes/main.scene.json"]}
SCENE = '{"name": "main", "root": {"type": "Node", "name": "root", "children": []}}\n'


def zip_files(name, files, top=""):
    path = os.path.join(HERE, name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for rel, data in files.items():
            info = zipfile.ZipInfo(top + rel, date_time=(2026, 11, 10, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if rel.endswith(".png") else zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def png(w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def main():
    shot = png(320, 180, (70, 130, 200))
    open(os.path.join(HERE, "hello_shot.png"), "wb").write(shot)
    plugin = {"plugin.json": json.dumps(PLUGIN_JSON, indent=2), "main.lua": MAIN_LUA, "README.md": README}
    # (In a top folder, as GitHub's zips are: the installer leaves it out.)
    sha1 = zip_files("registry_hello_zz-1.0.0.zip", plugin, top="registry_hello_zz-1.0.0/")
    sha2 = zip_files("registry_hello_zz-1.1.0.zip", dict(plugin, **{"plugin.json": json.dumps(PLUGIN_V2, indent=2)}))
    tmpl = {"template.json": json.dumps(TEMPLATE_JSON, indent=2), "project.json": json.dumps(PROJECT_JSON, indent=2),
            "scenes/main.scene.json": SCENE, "preview.png": png(160, 90, (60, 160, 90))}
    sha3 = zip_files("registry_blank_zz.zip", tmpl)
    sha4 = zip_files("evil_zz.zip", {"plugin.json": "{}", "../escaped_zz.txt": "outside"})
    net = dict(plugin, **{"plugin.json": json.dumps(dict(PLUGIN_JSON, permissions=["network"]), indent=2)})
    sha5 = zip_files("sneaky_zz.zip", net)
    common = {"author": "Rayzr tests", "license": "MIT", "repo": "example/registry-fixture"}
    entries = [
        dict(common, id="registry_hello_zz", kind="plugin", name="Registry Hello ZZ", version="1.0.0",
             description="Prints a line when it loads. (The registry drive installs it.)",
             url="registry_hello_zz-1.0.0.zip", sha256=sha1, rayzr=">=1.0.0", screenshot="hello_shot.png",
             tags=["test", "hello"], permissions=[]),
        dict(common, id="registry_blank_zz", kind="template", name="Registry Blank ZZ", version="1.0.0",
             description="An empty project: one scene.", url="registry_blank_zz.zip", sha256=sha3, tags=["test"]),
        dict(common, id="wrong_hash_zz", kind="plugin", name="Wrong Hash ZZ", version="1.0.0",
             description="Its zip isn't the one the index names.", url="registry_hello_zz-1.0.0.zip", sha256="0" * 64),
        dict(common, id="future_zz", kind="plugin", name="Future ZZ", version="1.0.0",
             description="Needs an editor from the future.", url="registry_hello_zz-1.0.0.zip", sha256=sha1,
             rayzr=">=99.0.0"),
        {"id": "Bad Id", "kind": "plugin", "version": "1", "url": "x.zip", "sha256": sha1},
        {"id": "no_hash_zz", "kind": "template", "version": "1", "url": "x.zip"},
    ]
    json.dump({"format": 1, "entries": entries}, open(os.path.join(HERE, "index.json"), "w"), indent=2)
    # The update: the same plugin at 1.1.0.
    entries[0] = dict(entries[0], version="1.1.0", url="registry_hello_zz-1.1.0.zip", sha256=sha2)
    json.dump({"format": 1, "entries": entries}, open(os.path.join(HERE, "index_v2.json"), "w"), indent=2)
    print("evil", sha4, "sneaky", sha5)
    json.dump({"evil_zz.zip": sha4, "sneaky_zz.zip": sha5}, open(os.path.join(HERE, "extra_sha256.json"), "w"), indent=2)


if __name__ == "__main__":
    sys.exit(main())
