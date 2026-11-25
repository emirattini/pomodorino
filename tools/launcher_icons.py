#!/usr/bin/env python3
"""Launcher icons at the size each watch in manifest.xml expects, from the SDK's device profiles.

The icon in resources/drawables/ (54 px, Forerunner 165) is the default. For every screen size the most
common icon size among our watches goes to resources-round-<W>x<W>/drawables/; a watch that differs from its
screen size's icon gets its own resources-<device>/drawables/. Connect IQ picks the most specific folder.

Usage: tools/launcher_icons.py      (after adding watches to manifest.xml)
Source: docs/icons/photo/vine_single_360.png (photo: Luc Viatour, CC BY-SA 3.0).
"""
import json
import os
import re
import shutil
from collections import Counter, defaultdict

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEVICES = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")
SOURCE = os.path.join(ROOT, "docs/icons/photo/vine_single_360.png")
DEFAULT = 54  # resources/drawables/launcher_icon.png
DRAWABLES_XML = os.path.join(ROOT, "resources/drawables/drawables.xml")


def watches():
    manifest = open(os.path.join(ROOT, "manifest.xml")).read()
    for device in re.findall(r'<iq:product id="([^"]+)"', manifest):
        c = json.load(open(os.path.join(DEVICES, device, "compiler.json")))
        yield device, c["resolution"]["width"], c["launcherIcon"]["width"]


def write_icon(folder, size, source):
    os.makedirs(folder, exist_ok=True)
    source.resize((size, size), Image.LANCZOS).save(os.path.join(folder, "launcher_icon.png"), optimize=True)
    shutil.copy(DRAWABLES_XML, os.path.join(folder, "drawables.xml"))


def main():
    source = Image.open(SOURCE).convert("RGBA")
    by_width = defaultdict(list)
    for device, width, icon in watches():
        by_width[width].append((device, icon))

    # Start clean: remove icons this script made before (device folders that only hold drawables).
    for name in os.listdir(ROOT):
        path = os.path.join(ROOT, name, "drawables")
        if name.startswith("resources-") and os.path.isdir(path):
            shutil.rmtree(path)
            if not os.listdir(os.path.join(ROOT, name)):
                os.rmdir(os.path.join(ROOT, name))

    for width, items in sorted(by_width.items()):
        common = Counter(icon for _, icon in items).most_common(1)[0][0]
        if common != DEFAULT or width != 390:
            write_icon(os.path.join(ROOT, f"resources-round-{width}x{width}", "drawables"), common, source)
        base = common if (common != DEFAULT or width != 390) else DEFAULT
        for device, icon in items:
            if icon != base:
                write_icon(os.path.join(ROOT, f"resources-{device}", "drawables"), icon, source)
                print(f"  {device}: {icon} px")
        print(f"{width} px screens: {common} px icon ({len(items)} watches)")


if __name__ == "__main__":
    main()
