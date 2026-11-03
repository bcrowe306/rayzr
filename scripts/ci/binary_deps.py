#!/usr/bin/env python3
"""What a packaged binary needs from the machine it runs on (#330's install
checks): the shared libraries an ELF (Linux) or PE (Windows) file links, and
for ELF the newest glibc symbol version it needs. No tools needed (readelf,
dumpbin, objdump aren't on every runner or container).

  python3 scripts/ci/binary_deps.py [--check] FILE...

Prints one line per file: `FILE: needs a.so, b.so; glibc 2.34` (ELF) or
`FILE: imports A.dll, B.dll` (PE). With --check, exits 1 when a PE file
imports a DLL a fresh Windows 10 / 11 doesn't have (the Visual C++ runtime:
VCRUNTIME140.dll, MSVCP140.dll ...) and it isn't next to the file, or an ELF
file needs a glibc newer than RAYZR_MAX_GLIBC (default 2.35: Ubuntu 22.04,
the oldest Linux the .deb supports).
"""
import os
import struct
import sys

# DLLs every Windows 10 / 11 has (the system's, the Universal CRT since 10).
WINDOWS_SYSTEM = {
    "kernel32.dll", "user32.dll", "gdi32.dll", "shell32.dll", "ole32.dll", "oleaut32.dll", "advapi32.dll",
    "winmm.dll", "ws2_32.dll", "comdlg32.dll", "comctl32.dll", "shlwapi.dll", "dbghelp.dll", "opengl32.dll",
    "ntdll.dll", "bcrypt.dll", "crypt32.dll", "secur32.dll", "version.dll", "imm32.dll", "setupapi.dll",
    "dwmapi.dll", "uxtheme.dll", "userenv.dll", "iphlpapi.dll", "psapi.dll", "synchronization.dll",
    "ucrtbase.dll", "msvcrt.dll", "mswsock.dll", "winhttp.dll", "wininet.dll", "dinput8.dll", "xinput1_4.dll",
    "hid.dll", "cfgmgr32.dll", "powrprof.dll", "dsound.dll", "mfplat.dll", "mf.dll", "mfreadwrite.dll",
    "propsys.dll", "shcore.dll", "ntdll.dll", "rpcrt4.dll", "normaliz.dll", "wldap32.dll", "netapi32.dll",
    "d3d11.dll", "dxgi.dll", "d3dcompiler_47.dll", "avrt.dll", "ksuser.dll", "mmdevapi.dll",
}


def elf_info(data):
    """(needed libraries, newest GLIBC_x.y) of an ELF64 little-endian file."""
    if data[4] != 2 or data[5] != 1:
        return None
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    secs = []
    for i in range(shnum):
        o = shoff + i * shentsize
        name, typ, _flags, _addr, off, size, link, _info, _align, entsize = struct.unpack_from("<IIQQQQIIQQ", data, o)
        secs.append((name, typ, off, size, link, entsize))

    def cstr(off):
        return data[off:data.index(b"\0", off)].decode("utf-8", "replace")

    needed, versions = [], []
    for name, typ, off, size, link, entsize in secs:
        strtab = secs[link][2] if link < len(secs) else 0
        if typ == 6:  # SHT_DYNAMIC
            for j in range(size // 16):
                tag, val = struct.unpack_from("<qQ", data, off + j * 16)
                if tag == 1:  # DT_NEEDED
                    needed.append(cstr(strtab + val))
        elif typ == 0x6FFFFFFE:  # SHT_GNU_verneed
            o = off
            while True:
                _ver, cnt, _file, aux, nxt = struct.unpack_from("<HHIII", data, o)
                a = o + aux
                for _ in range(cnt):
                    _hash, _flags, _other, vname, anext = struct.unpack_from("<IHHII", data, a)
                    versions.append(cstr(strtab + vname))
                    if anext == 0:
                        break
                    a += anext
                if nxt == 0:
                    break
                o += nxt
    glibc = [v[6:] for v in versions if v.startswith("GLIBC_") and v[6:7].isdigit()]
    newest = max(glibc, key=lambda v: tuple(int(x) for x in v.split(".") if x.isdigit()), default="")
    return needed, newest


def pe_imports(data):
    """The DLLs a PE file imports (normal and delay-loaded)."""
    pe, = struct.unpack_from("<I", data, 0x3C)
    if data[pe:pe + 4] != b"PE\0\0":
        return None
    nsec, = struct.unpack_from("<H", data, pe + 6)
    optsize, = struct.unpack_from("<H", data, pe + 20)
    opt = pe + 24
    magic, = struct.unpack_from("<H", data, opt)
    dirs = opt + (112 if magic == 0x20B else 96)
    sections = []
    for i in range(nsec):
        o = opt + optsize + i * 40
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
        sections.append((vaddr, max(vsize, rawsize), rawptr))

    def off(rva):
        for vaddr, size, raw in sections:
            if vaddr <= rva < vaddr + size:
                return rva - vaddr + raw
        return None

    def cstr(o):
        return data[o:data.index(b"\0", o)].decode("ascii", "replace")

    dlls = []
    for index, entry, name_at in ((1, 20, 12), (13, 32, 4)):  # imports, delay imports
        rva, _size = struct.unpack_from("<II", data, dirs + index * 8)
        if rva == 0 or off(rva) is None:
            continue
        o = off(rva)
        while True:
            name_rva, = struct.unpack_from("<I", data, o + name_at)
            if name_rva == 0:
                break
            if off(name_rva) is not None:
                dlls.append(cstr(off(name_rva)))
            o += entry
    return dlls


def main():
    args = sys.argv[1:]
    check = "--check" in args
    files = [a for a in args if a != "--check"]
    max_glibc = os.environ.get("RAYZR_MAX_GLIBC", "2.35")
    bad = 0
    for f in files:
        data = open(f, "rb").read()
        if data[:4] == b"\x7fELF":
            needed, glibc = elf_info(data)
            print(f"{f}: needs {', '.join(needed) or 'nothing'}; glibc {glibc or '-'}")
            vt = lambda v: tuple(int(x) for x in v.split("."))
            if check and glibc and vt(glibc) > vt(max_glibc):
                print(f"FAIL: {f} needs glibc {glibc}, newer than {max_glibc}")
                bad = 1
        elif data[:2] == b"MZ":
            dlls = pe_imports(data) or []
            print(f"{f}: imports {', '.join(dlls) or 'nothing'}")
            here = {n.lower() for n in os.listdir(os.path.dirname(os.path.abspath(f)))}
            for d in dlls:
                low = d.lower()
                if low in WINDOWS_SYSTEM or low.startswith("api-ms-win-") or low.startswith("ext-ms-") or low in here:
                    continue
                print(f"{'FAIL' if check else 'note'}: {f} imports {d}: not part of Windows and not next to it"
                      + (" (the Visual C++ runtime: link it statically, /MT)" if low.startswith(("vcruntime", "msvcp", "concrt")) else ""))
                bad = 1 if check else bad
        else:
            print(f"{f}: not an ELF or PE file")
    return bad


if __name__ == "__main__":
    sys.exit(main())
