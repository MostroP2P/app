#!/usr/bin/env python3
"""Build the flags font from Noto Color Emoji.

Linux and Windows ship no flag glyphs, so a flag left to the OS prints as two
boxed letters (#731). The app bundles the flags of Noto Color Emoji instead
and puts them in both themes' `fontFamilyFallback` (DS-TYP-8,
`lib/core/app_theme.dart`).

Source: the CBDT build Noto publishes for Windows
(`NotoColorEmoji_WindowsCompatible.ttf`, the one that carries an empty `glyf`
table for the Windows font loader), pinned to a commit and checked by hash.
CBDT (PNG bitmaps) is what FreeType (Android, Linux, web) and DirectWrite
(Windows) both draw; the COLRv1 build of the same flags is twice the size and
DirectWrite draws it only on Windows 11. Core Text draws neither, which is why
iOS and macOS keep their own emoji font.

The subset keeps the 26 regional indicators and every flag they spell, since
a node's region can be any country, plus the two globes: U+1F30D, which
`fiat.json` uses for the CFA francs, and U+1F310, the default node's region in
`rust/src/config.rs`. Licence: SIL OFL 1.1, `assets/fonts/noto_flags/LICENSE.txt`.

Run after changing the pin or the code points:

    python3 -m venv /tmp/flags-venv
    /tmp/flags-venv/bin/pip install fonttools
    /tmp/flags-venv/bin/python tool/flags_font/build_font.py
"""

import hashlib
import json
import re
import sys
import tempfile
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/fonts/noto_flags/NotoFlags.ttf"
FIAT = ROOT / "assets/data/fiat.json"
NODES = ROOT / "rust/src/config.rs"

COMMIT = "1ffdd21391dd1f25c081fa93a9dea0c7c029442b"
SOURCE = (
    "https://raw.githubusercontent.com/googlefonts/noto-emoji/"
    f"{COMMIT}/2D/fonts/NotoColorEmoji_WindowsCompatible.ttf"
)
SHA256 = "2c7ede2f5438f9c1da098778bd681535933a345334008bb03fc51119f6b1cd72"

REGIONAL_INDICATORS = range(0x1F1E6, 0x1F1FF + 1)
EARTH_AFRICA = 0x1F30D
GLOBE_WITH_MERIDIANS = 0x1F310


def download(dest: Path) -> None:
    with urllib.request.urlopen(SOURCE) as response:
        data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SHA256:
        sys.exit(f"source hash {digest} does not match the pin {SHA256}")
    dest.write_bytes(data)


def build(source: Path) -> None:
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    font = TTFont(source)
    subsetter = subset.Subsetter(options)
    subsetter.populate(
        unicodes=[*REGIONAL_INDICATORS, EARTH_AFRICA, GLOBE_WITH_MERIDIANS]
    )
    subsetter.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)


def check() -> None:
    """Every flag a currency or a trusted node shows is in the font, as one
    glyph."""
    font = TTFont(OUT)
    cmap = font.getBestCmap()
    ligatures = set()
    for lookup in font["GSUB"].table.LookupList.Lookup:
        for table in lookup.SubTable:
            for first, entries in getattr(table, "ligatures", {}).items():
                for entry in entries:
                    ligatures.add((first, *entry.Component))
    symbols = [(c["code"], c["flag"]) for c in json.loads(FIAT.read_text())]
    for region in re.findall(r'region: "([^"]+)"', NODES.read_text()):
        symbols.append((region, region.split(" ")[0]))
    missing = []
    for name, symbol in symbols:
        glyphs = tuple(cmap.get(ord(c)) for c in symbol)
        if None in glyphs or (len(glyphs) > 1 and glyphs not in ligatures):
            missing.append(name)
    if missing:
        sys.exit(f"flags missing from {OUT.name}: {', '.join(missing)}")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "source.ttf"
        download(source)
        build(source)
    check()
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
