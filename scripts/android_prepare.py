#!/usr/bin/env python3
"""Prepares the Android runner's source tree (scripts/build_android_runner.sh).

Copies engine/ (without tests), runner/android/ and ui/ into OUT and points
the engine's Box2D at bindings that link the Box2D built with the NDK
(Odin's vendor bindings stop at compile time without their prebuilt
library for the target). The originals are not touched.

usage: android_prepare.py REPO OUT ODIN_ROOT
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_prepare import copy_tree, patch_file  # noqa: E402


def main():
    repo, out, odin_root = sys.argv[1], sys.argv[2], sys.argv[3]
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    copy_tree(os.path.join(repo, "engine"), os.path.join(out, "engine"), skip_tests=True)
    copy_tree(os.path.join(repo, "runner", "android"), os.path.join(out, "runner", "android"))
    copy_tree(os.path.join(repo, "ui"), os.path.join(out, "ui"), skip_tests=True)
    # Box2D: Odin's bindings, the library being ours (linked afterwards).
    b2src = os.path.join(odin_root, "vendor", "box2d")
    b2 = os.path.join(out, "engine", "box2d_android")
    os.makedirs(b2)
    for f in os.listdir(b2src):
        if f.endswith(".odin") and f != "box2d_wasm.odin":
            shutil.copy2(os.path.join(b2src, f), os.path.join(b2, f))
    patch_file(os.path.join(b2, "box2d.odin"), lambda t: re.sub(r'@\(private\) LIB_PATH :: "lib/box2d_other\.a"', '@(private) LIB_PATH :: "libbox2d_android.a"', t))
    open(os.path.join(b2, "libbox2d_android.a"), "w").close()
    for f in os.listdir(os.path.join(out, "engine")):
        if f.endswith(".odin"):
            patch_file(os.path.join(out, "engine", f), lambda t: t.replace('import b2 "vendor:box2d"', 'import b2 "box2d_android"'))
    print("prepared", out)


if __name__ == "__main__":
    main()
