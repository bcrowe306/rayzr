#!/usr/bin/env python3
"""Tests scripts/registry/check_index.py against the editor's registry fixture
(tests/drive/fixtures/registry): the good entries pass, the bad ones are each
reported. python3 -I scripts/registry/test_check_index.py"""
import json, os, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "registry"))
import check_index  # noqa: E402

FIX = os.path.join(ROOT, "tests", "drive", "fixtures", "registry")


def main():
    index = json.load(open(os.path.join(FIX, "index.json")))
    problems = check_index.check(os.path.join(FIX, "index.json"), download=True)
    bad = {p.split(":", 1)[0] for p in problems}
    assert bad == {"wrong_hash_zz", "Bad Id", "no_hash_zz"}, problems
    # Only the good entries, next to their zips: no problems.
    with tempfile.TemporaryDirectory() as tmp:
        good = [e for e in index["entries"] if e["id"] in ("registry_hello_zz", "registry_blank_zz", "future_zz")]
        p = os.path.join(tmp, "index.json")
        json.dump({"format": 1, "entries": [dict(e, url=os.path.join(FIX, e["url"])) for e in good]}, open(p, "w"))
        assert check_index.check(p, download=True) == []
        # A plugin asking for more than its entry lists; a zip escaping its folder.
        extra = json.load(open(os.path.join(FIX, "extra_sha256.json")))
        base = dict(good[0], version="1.0.0")
        sneaky = dict(base, id="sneaky_zz", url=os.path.join(FIX, "sneaky_zz.zip"), sha256=extra["sneaky_zz.zip"])
        evil = dict(base, id="evil_zz", url=os.path.join(FIX, "evil_zz.zip"), sha256=extra["evil_zz.zip"])
        json.dump({"entries": [sneaky, evil]}, open(p, "w"))
        problems = check_index.check(p, download=True)
        assert any("sneaky_zz" in x and "network" in x for x in problems), problems
        assert any("evil_zz" in x and "outside" in x for x in problems), problems
    print("check_index: ok")


if __name__ == "__main__":
    main()
