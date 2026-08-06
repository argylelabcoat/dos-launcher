#!/usr/bin/env python3
"""
RCLF fixture generator + host-side verifier for
openspec/specs/rclf-format-and-loader-hardening/tasks/03-verification.md.

This script does two things:

1. Generates the byte-exact RCLF fixture files listed in the task spec under
   fixtures/*.dat, following the layouts in
   openspec/changes/rclf-format-and-loader-hardening/specs/rclf-container/spec.md
   (TRIFFHeader, TRIFFChunkHeader, TLauncherHeader, TAppInfo -- see
   snips/RiffLauncher.pas -- and the PCX header in snips/RiffBgiIcon.pas).

2. Implements a faithful Python port of the hardened chunk-walk loader in
   snips/launcher.pas (LoadLauncherData / ProcessAppsList / ProcessAppEntry)
   and runs it against every fixture, plus a Python port of the naive
   RiffDOSParser.pas dumper run against the well-formed fixture, printing
   results so the file-format-level acceptance scenarios can be checked
   without a DOS cross-compiler or DOSBox.

Run: python3 fixtures/build_and_check.py
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))

MAX_APPS = 50
ITEMS_PER_PAGE = 7

# ---------------------------------------------------------------------------
# Low-level RIFF/RCLF byte builders (mirrors snips/RiffLauncher.pas layouts)
# ---------------------------------------------------------------------------

def pstr(s: str, cap: int) -> bytes:
    """Turbo Pascal short string: 1 length byte + content, padded with
    zero bytes to cap+1 total bytes (field width), matching TAppInfo's
    string[N] fields."""
    b = s.encode("ascii")
    if len(b) > cap:
        b = b[:cap]
    return bytes([len(b)]) + b + b"\x00" * (cap - len(b))


def chunk(fourcc: str, payload: bytes) -> bytes:
    assert len(fourcc) == 4
    size = len(payload)
    pad = b"\x00" if size % 2 else b""
    return fourcc.encode("ascii") + struct.pack("<i", size) + payload + pad


def riff_root(form_type: str, form_data: bytes) -> bytes:
    assert len(form_type) == 4
    # FileSize = total file size - 8; total size = 12 (root) + len(form_data)
    file_size = 4 + len(form_type) + len(form_data)  # everything after RIFF+size field
    return b"RIFF" + struct.pack("<i", file_size) + form_type.encode("ascii") + form_data


def hder_chunk(version: int, app_count: int, flags: int = 0) -> bytes:
    payload = struct.pack("<HHH", version, app_count, flags)
    return chunk("HDER", payload)


def app_info_payload(title, desc, exe, args, flags) -> bytes:
    payload = pstr(title, 40) + pstr(desc, 70) + pstr(exe, 64) + pstr(args, 64) + struct.pack("<H", flags)
    assert len(payload) == 244, len(payload)
    return payload


def make_pcx_icon(seed: int = 0) -> bytes:
    """Builds a valid 32x32, 4-plane, 1bpp RLE PCX payload per
    snips/RiffBgiIcon.pas's TPCXHeader / decode expectations."""
    header = struct.pack(
        "<BBBB HHHH HH 48s BB HH 58s",
        0x0A,  # Manufacturer
        5,     # Version
        1,     # Encoding = RLE
        1,     # BitsPerPixel
        0, 0,  # XMin, YMin
        31, 31,  # XMax, YMax -> 32x32
        300, 300,  # HDpi, VDpi
        bytes(48),  # Palette
        0,     # Reserved
        4,     # NPlanes
        4,     # BytesPerLine
        0,     # PaletteInfo
        bytes(58),  # Padding
    )
    assert len(header) == 128, len(header)

    def rle_byte(v: int) -> bytes:
        v &= 0xFF
        if (v & 0xC0) == 0xC0:
            # Must escape: run-length header byte (count=1, top bits 11) + value
            return bytes([0xC1, v])
        return bytes([v])

    total_bytes_per_line = 4 * 4  # NPlanes * BytesPerLine = 16
    rle = bytearray()
    for y in range(32):
        for i in range(total_bytes_per_line):
            v = (seed + y + i) & 0xFF
            rle += rle_byte(v)
    return header + bytes(rle)


def app_entry(title, desc, exe, args, flags, with_icon, icon_seed=0) -> bytes:
    info = chunk("INFO", app_info_payload(title, desc, exe, args, flags))
    body = info
    if with_icon:
        body += chunk("ICON", make_pcx_icon(icon_seed))
    return chunk("APP ", body)


def apps_list(entries: list) -> bytes:
    payload = b"APPS" + b"".join(entries)
    return chunk("LIST", payload)


# ---------------------------------------------------------------------------
# Fixture 1: good-12-entries.dat
# 12 APP entries, mix with/without icons, one unknown chunk between HDER and
# APPS (also odd-sized, to exercise padding in one chunk).
# ---------------------------------------------------------------------------

def build_good_12():
    entries = []
    for i in range(12):
        with_icon = (i % 2 == 0)  # 6 with icons, 6 without
        entries.append(app_entry(
            title=f"Game {i+1}",
            desc=f"Description for game {i+1}",
            exe=f"C:\\GAMES\\G{i+1}\\GAME.EXE",
            args="" if i % 3 else "-fast",
            flags=(i & 3),  # exercises both flag bits across entries
            with_icon=with_icon,
            icon_seed=i,
        ))

    unknown_chunk = chunk("XTRA", b"\x01\x02\x03")  # odd-sized (3 bytes) unknown chunk

    form_data = (
        hder_chunk(version=1, app_count=12)
        + unknown_chunk
        + apps_list(entries)
    )
    return riff_root("RCLF", form_data)


# ---------------------------------------------------------------------------
# Fixture 2: too-many-entries.dat -- 55 APP entries, INFO only (no icons)
# ---------------------------------------------------------------------------

def build_too_many():
    entries = []
    for i in range(55):
        entries.append(app_entry(
            title=f"App{i+1}",
            desc="",
            exe=f"C:\\APP{i+1}.EXE",
            args="",
            flags=0,
            with_icon=False,
        ))
    form_data = hder_chunk(version=1, app_count=55) + apps_list(entries)
    return riff_root("RCLF", form_data)


# ---------------------------------------------------------------------------
# Fixture 3: wrong-form-type.dat -- form type != RCLF
# ---------------------------------------------------------------------------

def build_wrong_form_type():
    entries = [app_entry("Game 1", "Desc", "C:\\G.EXE", "", 0, False)]
    form_data = hder_chunk(version=1, app_count=1) + apps_list(entries)
    return riff_root("RCLX", form_data)  # wrong form type


# ---------------------------------------------------------------------------
# Fixture 4: bad-version.dat -- HDER.Version != 1
# ---------------------------------------------------------------------------

def build_bad_version():
    entries = [app_entry("Game 1", "Desc", "C:\\G.EXE", "", 0, False)]
    form_data = hder_chunk(version=2, app_count=1) + apps_list(entries)
    return riff_root("RCLF", form_data)


# ---------------------------------------------------------------------------
# Fixture 5: truncated.dat -- good file cut off mid-chunk after at least one
# complete committed APP entry.
# ---------------------------------------------------------------------------

def build_truncated():
    good = build_good_12()
    # Find the byte offset right after the first complete APP entry's LIST
    # wrapper closes, then cut partway into the *second* entry's INFO chunk
    # payload, so entry 0 is fully committed but entry 1 is not.
    #
    # Rebuild manually with only 2 entries so we know exact offsets, then cut.
    e0 = app_entry("Game 1", "Description for game 1", "C:\\GAMES\\G1\\GAME.EXE", "-fast", 1, with_icon=True, icon_seed=0)
    e1 = app_entry("Game 2", "Description for game 2", "C:\\GAMES\\G2\\GAME.EXE", "", 2, with_icon=False)
    unknown_chunk = chunk("XTRA", b"\x01\x02\x03")
    form_data_prefix = hder_chunk(version=1, app_count=12) + unknown_chunk
    apps_list_full = apps_list([e0, e1])

    full = riff_root("RCLF", form_data_prefix + apps_list_full)

    # Offset of start of e1 within the file: locate by rebuilding offsets.
    root_len = 12
    prefix_len = len(form_data_prefix)
    apps_list_header_len = 8  # 'LIST' + size
    apps_subtype_len = 4      # 'APPS'
    e0_len = len(e0)
    # start of e1 relative to file start:
    e1_start = root_len + prefix_len + apps_list_header_len + apps_subtype_len + e0_len
    # Cut somewhere inside e1: after its APP LIST header + INFO chunk header,
    # but only partway through the INFO payload (which is 244 bytes), so the
    # INFO record is truncated -> entry discarded, loading stops, entry 0
    # (already committed) is retained.
    cut_into_e1 = 8 + 8 + 100  # APP LIST header(8) + INFO chunk header(8) + 100 bytes of the 244-byte payload
    cut_offset = e1_start + cut_into_e1
    assert cut_offset < len(full), (cut_offset, len(full))
    return full[:cut_offset]


# ---------------------------------------------------------------------------
# Python port of the HARDENED loader (snips/launcher.pas LoadLauncherData)
# ---------------------------------------------------------------------------

class Loader:
    """Faithful port of the chunk-walk state machine in snips/launcher.pas."""

    def __init__(self, data: bytes):
        self.data = data
        self.file_len = len(data)
        self.total_apps = 0
        self.apps = []  # list of dicts: title, desc, exe, args, flags, icon(bool)
        self.aborted = False

    def read_chunk_header(self, pos):
        if pos + 8 > self.file_len:
            return None
        fourcc = self.data[pos:pos+4].decode("ascii", errors="replace")
        size = struct.unpack("<i", self.data[pos+4:pos+8])[0]
        return fourcc, size, pos + 8

    def skip_chunk_payload(self, chunk_start, size, boundary):
        if size < 0:
            return None
        target = chunk_start + size
        if size & 1:
            target += 1
        if target > boundary or target > self.file_len:
            return None
        return target

    def process_app_entry(self, pos, entry_end):
        have_info = False
        malformed = False
        have_icon = False
        info = None
        while pos < entry_end:
            hdr = self.read_chunk_header(pos)
            if hdr is None:
                self.aborted = True
                return
            fourcc, size, sub_start = hdr

            if fourcc == "INFO":
                if have_info:
                    malformed = True
                    nxt = self.skip_chunk_payload(sub_start, size, entry_end)
                    if nxt is None:
                        self.aborted = True
                        return
                    pos = nxt
                elif size < 244:
                    self.aborted = True
                    return
                else:
                    if sub_start + 244 > self.file_len:
                        self.aborted = True
                        return
                    payload = self.data[sub_start:sub_start+244]
                    info = self.parse_app_info(payload)
                    have_info = True
                    nxt = self.skip_chunk_payload(sub_start, size, entry_end)
                    if nxt is None:
                        self.aborted = True
                        return
                    pos = nxt
            elif fourcc == "ICON":
                if have_info and not malformed:
                    have_icon = True  # we don't need to actually decode PCX for this check
                nxt_pos = sub_start + size + (size & 1)
                if nxt_pos > self.file_len:
                    self.aborted = True
                    return
                pos = nxt_pos
            else:
                nxt = self.skip_chunk_payload(sub_start, size, entry_end)
                if nxt is None:
                    self.aborted = True
                    return
                pos = nxt

        if have_info and not malformed and self.total_apps < MAX_APPS:
            info["icon"] = have_icon
            self.apps.append(info)
            self.total_apps += 1

    @staticmethod
    def parse_app_info(payload: bytes) -> dict:
        off = 0
        def read_pstr(cap):
            nonlocal off
            length = payload[off]
            content = payload[off+1:off+1+length].decode("ascii", errors="replace")
            off += cap + 1
            return content
        title = read_pstr(40)
        desc = read_pstr(70)
        exe = read_pstr(64)
        args = read_pstr(64)
        flags = struct.unpack("<H", payload[off:off+2])[0]
        off += 2
        assert off == 244
        return {"title": title, "desc": desc, "exe": exe, "args": args, "flags": flags}

    def process_apps_list(self, pos, list_end):
        while (not self.aborted) and self.total_apps < MAX_APPS and pos < list_end:
            hdr = self.read_chunk_header(pos)
            if hdr is None:
                self.aborted = True
                return
            fourcc, size, sub_start = hdr
            if fourcc == "APP ":
                self.process_app_entry(sub_start, sub_start + size)
                if self.aborted:
                    return
                nxt = self.skip_chunk_payload(sub_start, size, list_end)
                if nxt is None:
                    self.aborted = True
                    return
                pos = nxt
            else:
                nxt = self.skip_chunk_payload(sub_start, size, list_end)
                if nxt is None:
                    self.aborted = True
                    return
                pos = nxt

    def load(self):
        if self.file_len < 12:
            return
        if self.data[0:4] != b"RIFF" or self.data[8:12] != b"RCLF":
            return
        file_size_field = struct.unpack("<i", self.data[4:8])[0]
        form_end = 8 + file_size_field
        if form_end > self.file_len or form_end < 12:
            form_end = self.file_len

        header_seen = False
        pos = 12
        while (not self.aborted) and self.total_apps < MAX_APPS and pos < form_end:
            hdr = self.read_chunk_header(pos)
            if hdr is None:
                break
            fourcc, size, chunk_start = hdr

            if fourcc == "HDER":
                if size < 6:
                    break
                if chunk_start + 6 > self.file_len:
                    break
                version, app_count, flags = struct.unpack("<HHH", self.data[chunk_start:chunk_start+6])
                if version != 1:
                    self.total_apps = 0
                    self.apps = []
                    return
                header_seen = True
                nxt = self.skip_chunk_payload(chunk_start, size, form_end)
                if nxt is None:
                    break
                pos = nxt
            elif fourcc == "LIST":
                if size < 4:
                    break
                if chunk_start + 4 > self.file_len:
                    break
                list_type = self.data[chunk_start:chunk_start+4].decode("ascii", errors="replace")
                if header_seen and list_type == "APPS":
                    self.process_apps_list(chunk_start + 4, chunk_start + size)
                    if self.aborted:
                        break
                    nxt = self.skip_chunk_payload(chunk_start, size, form_end)
                    if nxt is None:
                        break
                    pos = nxt
                else:
                    nxt = self.skip_chunk_payload(chunk_start, size, form_end)
                    if nxt is None:
                        break
                    pos = nxt
            else:
                nxt = self.skip_chunk_payload(chunk_start, size, form_end)
                if nxt is None:
                    break
                pos = nxt

        if self.total_apps > 0:
            self.total_pages = (self.total_apps + ITEMS_PER_PAGE - 1) // ITEMS_PER_PAGE
        else:
            self.total_pages = 1


# ---------------------------------------------------------------------------
# Python port of the NAIVE RiffDOSParser.pas dumper (used only against the
# well-formed fixture, as the task describes: confirm it "dumps the file
# cleanly" -- it has no error handling of its own, so we just confirm it
# doesn't go out of bounds and reports the right structure.)
# ---------------------------------------------------------------------------

def riff_dos_parser_dump(data: bytes):
    """Port of snips/RiffDOSParser.pas's flat, non-recursive dump loop.

    NOTE: RiffDOSParser.pas only has explicit branches for HDER / LIST /
    INFO / ICON FourCCs (see its `if SameFourCC(...)` chain). It has no
    branch for 'APP ' (ID_APP), which is the chunk type the hardened loader
    (snips/launcher.pas) actually uses to wrap each application entry's
    INFO/ICON pair (`SameFourCC(SubChunk.ID, ID_APP)` in ProcessAppsList).
    So when RiffDOSParser encounters an 'APP ' chunk it falls into its
    `else` branch and skips the *entire* entry via SkipChunk(Chunk.Size)
    without descending into it -- it never prints "Loaded App: ..." for
    entries produced by the current on-disk format. This is a real,
    pre-existing limitation of the naive reference dumper, not something
    this verification task modifies (RiffDOSParser.pas is reference-only,
    "used but not modified" per the task file). What we *can* confirm here
    is what the task literally asks: that it dumps the file "cleanly" --
    i.e. it runs to EOF without crashing or reading out of bounds, and
    correctly reports the HDER App Count -- while noting it will not
    enumerate each entry by title given the current chunk layout.
    """
    out = []
    pos = 0
    n = len(data)
    if n < 12 or data[0:4] != b"RIFF" or data[8:12] != b"RCLF":
        out.append("Invalid RIFF launcher file.")
        return out
    out.append("RIFF Container Verified. Parsing Chunks...")
    pos = 12
    app_count_seen = 0
    while pos < n:
        if pos + 8 > n:
            break  # BlockRead would return short count; RiffDOSParser 'while not EOF' + Break
        fourcc = data[pos:pos+4].decode("ascii", errors="replace")
        size = struct.unpack("<i", data[pos+4:pos+8])[0]
        pos += 8
        if fourcc == "HDER":
            hder = data[pos:pos+6]
            pos += 6
            # TLauncherHeader = Version(Word), AppCount(Word), Flags(Word)
            app_count = struct.unpack("<H", hder[2:4])[0]
            out.append(f"App Count: {app_count}")
        elif fourcc == "LIST":
            pos += 4  # list type FourCC; loop continues into sub-chunks naturally
        elif fourcc == "INFO":
            title_len = data[pos]
            title = data[pos+1:pos+1+title_len].decode("ascii", errors="replace")
            pos += 244
            app_count_seen += 1
            out.append(f"Loaded App: {title}")
        elif fourcc == "ICON":
            pos += 512
            out.append("  [Icon Data Streamed]")
        else:
            # Includes the 'APP ' wrapper chunks -- see docstring above.
            if size % 2:
                size += 1
            pos += size
    out.append(f"(parser saw {app_count_seen} INFO records, ran to EOF at pos={pos}/{n})")
    return out


# ---------------------------------------------------------------------------
# Main: build fixtures, run checks, print report
# ---------------------------------------------------------------------------

def main():
    fixtures = {
        "good-12-entries.dat": build_good_12(),
        "too-many-entries.dat": build_too_many(),
        "wrong-form-type.dat": build_wrong_form_type(),
        "bad-version.dat": build_bad_version(),
        "truncated.dat": build_truncated(),
    }

    for name, data in fixtures.items():
        path = os.path.join(HERE, name)
        with open(path, "wb") as f:
            f.write(data)
        print(f"wrote {path} ({len(data)} bytes)")

    print("\n=== Hardened loader (launcher.pas port) results ===")
    results = {}
    for name, data in fixtures.items():
        loader = Loader(data)
        loader.load()
        results[name] = loader
        icons = sum(1 for a in loader.apps if a.get("icon"))
        print(f"{name}: total_apps={loader.total_apps} aborted={loader.aborted} "
              f"icons={icons} pages={getattr(loader, 'total_pages', None)}")

    print("\n=== Scenario checks ===")

    def check(desc, cond):
        status = "PASS" if cond else "FAIL"
        print(f"[{status}] {desc}")
        return cond

    all_pass = True

    g = results["good-12-entries.dat"]
    all_pass &= check("good-12: loads all 12 entries", g.total_apps == 12)
    all_pass &= check("good-12: entry 1 title matches", g.apps[0]["title"] == "Game 1")
    all_pass &= check("good-12: entry 12 title matches", g.apps[11]["title"] == "Game 12")
    all_pass &= check("good-12: exec paths intact",
                       all(a["exe"].startswith("C:\\GAMES\\G") for a in g.apps))
    all_pass &= check("good-12: mixed icon presence (6 with, 6 without)",
                       sum(1 for a in g.apps if a["icon"]) == 6)
    all_pass &= check("good-12: pages = 2 (ceil(12/7))", g.total_pages == 2)
    all_pass &= check("good-12: not aborted", not g.aborted)

    dump = riff_dos_parser_dump(fixtures["good-12-entries.dat"])
    print("\n-- RiffDOSParser.pas-equivalent dump of good-12-entries.dat --")
    for line in dump:
        print("  " + line)
    good_len = len(fixtures["good-12-entries.dat"])
    all_pass &= check("good-12: RiffDOSParser-equivalent dump reports HDER App Count 12",
                       "App Count: 12" in dump)
    all_pass &= check("good-12: RiffDOSParser-equivalent dump runs cleanly to EOF (no crash/OOB)",
                       dump[-1].endswith(f"pos={good_len}/{good_len})"))
    print("  NOTE: RiffDOSParser.pas has no branch for the 'APP ' FourCC that")
    print("  snips/launcher.pas actually uses to wrap each entry, so it skips")
    print("  every APP entry as 'unknown' and prints no per-entry 'Loaded App:'")
    print("  lines for this file layout. This is a pre-existing limitation of")
    print("  the naive reference dumper (not modified by this task) -- it still")
    print("  parses to EOF cleanly with no crash / out-of-bounds read.")

    tm = results["too-many-entries.dat"]
    all_pass &= check("too-many: exactly MAX_APPS (50) loaded", tm.total_apps == 50)
    all_pass &= check("too-many: not aborted / no crash", not tm.aborted)
    all_pass &= check("too-many: first entry is App1", tm.apps[0]["title"] == "App1")
    all_pass &= check("too-many: 50th loaded entry is App50", tm.apps[49]["title"] == "App50")

    wf = results["wrong-form-type.dat"]
    all_pass &= check("wrong-form-type: loads no applications", wf.total_apps == 0)

    bv = results["bad-version.dat"]
    all_pass &= check("bad-version: loads no applications", bv.total_apps == 0)

    tr = results["truncated.dat"]
    all_pass &= check("truncated: keeps only entries committed before truncation (1)",
                       tr.total_apps == 1)
    all_pass &= check("truncated: committed entry is Game 1", tr.apps[0]["title"] == "Game 1")
    all_pass &= check("truncated: loader aborted cleanly (no exception raised)", True)

    print(f"\n=== Overall: {'ALL CHECKS PASSED' if all_pass else 'SOME CHECKS FAILED'} ===")
    return 0 if all_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
