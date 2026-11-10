#!/usr/bin/env python3
"""Checks a plugin / template registry index.json (#296) as the editor reads
it (editor/registry.odin): every entry's fields, and with --download each
entry's zip - its SHA-256, the manifest at its top, no paths outside its
folder, and a plugin asking for no more permissions than the entry lists.
The rayzr-registry repository's CI runs it on pull requests; authors can run
it on their own index first (docs/editor/publishing.md).

    python3 -I scripts/registry/check_index.py index.json [--download]

Exit status 1 when anything is wrong (each problem printed).
"""
import argparse, hashlib, io, json, os, re, sys, urllib.parse, urllib.request, zipfile

FORMAT = 1
ID = re.compile(r"^[a-z0-9_][a-z0-9_-]{0,63}$")
SHA = re.compile(r"^[0-9a-f]{64}$")
VERSION = re.compile(r"^v?\d+(\.\d+){0,2}(-[0-9A-Za-z.-]+)?$")
PERMISSIONS = {"process", "network"}


def resolve(base, ref):
    if "://" in ref:
        return ref
    if os.path.isabs(ref):
        return "file://" + ref
    if "://" in base:
        return urllib.parse.urljoin(base, ref)
    return os.path.join(os.path.dirname(os.path.abspath(base)), ref)


def fetch(url):
    if "://" not in url:
        with open(url, "rb") as f:
            return f.read()
    req = urllib.request.Request(url, headers={"User-Agent": "rayzr-registry-check"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def check_zip(entry, data, problems):
    who = entry["id"]
    got = hashlib.sha256(data).hexdigest()
    if got != entry["sha256"]:
        problems.append(f"{who}: the zip's SHA-256 is {got}, the entry says {entry['sha256']}")
        return
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        problems.append(f"{who}: not a zip file")
        return
    names = [n for n in z.namelist() if not n.startswith("__MACOSX/")]
    for info in z.infolist():
        n = info.filename.replace("\\", "/")
        if n.startswith("/") or ":" in n or ".." in n.split("/"):
            problems.append(f"{who}: {info.filename!r} points outside the folder")
        if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            problems.append(f"{who}: {info.filename} uses compression {info.compress_type} (only stored and deflate)")
        if info.flag_bits & 1:
            problems.append(f"{who}: {info.filename} is encrypted")
    tops = {n.split("/", 1)[0] + "/" if "/" in n else "" for n in names}
    top = tops.pop() if len(tops) == 1 and "" not in tops else ""
    manifest = top + ("plugin.json" if entry["kind"] == "plugin" else "template.json")
    if manifest not in names:
        problems.append(f"{who}: no {manifest.split('/')[-1]} at the zip's top")
        return
    try:
        meta = json.loads(z.read(manifest))
    except ValueError:
        problems.append(f"{who}: {manifest} isn't valid JSON")
        return
    if entry["kind"] == "plugin":
        extra = set(meta.get("permissions", [])) - set(entry.get("permissions", []))
        if extra:
            problems.append(f"{who}: plugin.json asks for {sorted(extra)}, which the entry doesn't list")
        if meta.get("version") not in (None, entry["version"]):
            problems.append(f"{who}: plugin.json's version {meta.get('version')!r} isn't the entry's {entry['version']!r}")
    elif top + "project.json" not in names:
        problems.append(f"{who}: a template needs a project.json beside template.json")


def check(path, download):
    problems = []
    try:
        index = json.loads(fetch(path))
    except (OSError, ValueError) as e:
        return [f"{path}: can't read it ({e})"]
    if not isinstance(index, dict) or not isinstance(index.get("entries"), list):
        return [f"{path}: not an index (an object with \"entries\")"]
    if index.get("format", FORMAT) != FORMAT:
        problems.append(f"format must be {FORMAT}")
    seen = set()
    for i, e in enumerate(index["entries"], 1):
        if not isinstance(e, dict):
            problems.append(f"entry {i}: not an object")
            continue
        who = e.get("id") or f"entry {i}"
        def need(field, ok, why):
            if not ok:
                problems.append(f"{who}: {field} {why}")
        need("id", isinstance(e.get("id"), str) and ID.match(e["id"]), "must be lower-case letters, digits, _ or - (1-64)")
        need("id", e.get("id") not in seen, "is listed twice")
        seen.add(e.get("id"))
        need("kind", e.get("kind") in ("plugin", "template"), "must be plugin or template")
        need("version", isinstance(e.get("version"), str) and VERSION.match(e["version"]), "must be a version (1.2.3)")
        need("sha256", isinstance(e.get("sha256"), str) and SHA.match(e["sha256"]), "must be 64 lower-case hex digits")
        need("url", isinstance(e.get("url"), str) and e["url"], "is missing")
        for f in ("name", "author", "description", "license", "repo"):
            need(f, isinstance(e.get(f), str) and e[f].strip(), "is missing")
        if "rayzr" in e:
            need("rayzr", isinstance(e["rayzr"], str) and VERSION.match(e["rayzr"].lstrip(">= ")), "must be a version (\">=1.1.0\")")
        if "repo" in e:
            need("repo", re.match(r"^[\w.-]+/[\w.-]+$", str(e["repo"])), "must be owner/name")
        perms = e.get("permissions", [])
        need("permissions", isinstance(perms, list) and set(perms) <= PERMISSIONS, f"must be a list of {sorted(PERMISSIONS)}")
        if e.get("kind") == "template" and perms:
            problems.append(f"{who}: templates have no permissions")
        if download and not [p for p in problems if p.startswith(f"{who}:")]:
            try:
                check_zip(e, fetch(resolve(path, e["url"])), problems)
            except OSError as err:
                problems.append(f"{who}: can't download {e['url']} ({err})")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("index")
    ap.add_argument("--download", action="store_true", help="also fetch and check each entry's zip")
    a = ap.parse_args()
    problems = check(a.index, a.download)
    for p in problems:
        print(p)
    print(f"{a.index}: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
