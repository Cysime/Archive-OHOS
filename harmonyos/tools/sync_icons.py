#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sync Archive launcher icon & Lucide vector icons from the upstream Android
sources into HarmonyOS media resources without modifying any upstream files.
"""
import os
import re
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HARMONY = os.path.join(ROOT, "harmonyos")
LUCIDE_KT = os.path.join(
    ROOT, "app", "src", "main", "java", "com", "archive", "app", "ui", "design", "lucide", "LucideIcons.kt"
)
MEDIA_DIR = os.path.join(HARMONY, "entry", "src", "main", "resources", "base", "media")
APPSCOPE_MEDIA = os.path.join(HARMONY, "AppScope", "resources", "base", "media")


def camel_to_snake(name: str) -> str:
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()


def sync_app_icon() -> None:
    src = os.path.join(ROOT, "app", "src", "main", "res", "drawable-nodpi", "ic_app_logo.webp")
    if not os.path.exists(src):
        src = os.path.join(ROOT, "app", "src", "main", "res", "mipmap-xxxhdpi", "ic_launcher.webp")
    os.makedirs(MEDIA_DIR, exist_ok=True)
    os.makedirs(APPSCOPE_MEDIA, exist_ok=True)
    for dst in (
        os.path.join(APPSCOPE_MEDIA, "app_icon.png"),
        os.path.join(MEDIA_DIR, "app_icon.png"),
    ):
        subprocess.run(["sips", "-s", "format", "png", src, "--out", dst], check=True, stdout=subprocess.DEVNULL)
    start_icon = os.path.join(MEDIA_DIR, "start_window_icon.png")
    subprocess.run(
        ["sips", "-s", "format", "png", "-z", "256", "256", src, "--out", start_icon],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    print(f"Synced app_icon.png & 256x256 start_window_icon.png from {os.path.relpath(src, ROOT)}")


def sync_lucide_svgs() -> None:
    text = open(LUCIDE_KT, encoding="utf-8").read()
    pattern = re.compile(
        r'val\s+(\w+):\s+ImageVector\s+get\(\)\s*=\s*_\1\s*\?:\s*stroke\((.*?)\)\.also',
        re.DOTALL,
    )
    os.makedirs(MEDIA_DIR, exist_ok=True)
    count = 0
    for m in pattern.finditer(text):
        prop = m.group(1)
        body = m.group(2)
        filled = "filled = true" in body
        paths_match = re.search(r"paths\s*=\s*listOf\((.*?)\)", body, re.DOTALL)
        if not paths_match:
            continue
        paths = re.findall(r'"((?:[^"\\]|\\.)*)"', paths_match.group(1))
        if not paths:
            continue
        file_name = f"ic_{camel_to_snake(prop)}.svg"
        elements = []
        for raw_d in paths:
            d = raw_d.replace('\\"', '"').replace("\\\\", "\\")
            if filled:
                elements.append(f'  <path d="{d}" fill="#000000" stroke="none"/>')
            else:
                elements.append(
                    f'  <path d="{d}" fill="none" stroke="#000000" stroke-width="2" '
                    f'stroke-linecap="round" stroke-linejoin="round"/>'
                )
        svg = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\n'
            + "\n".join(elements)
            + "\n</svg>\n"
        )
        with open(os.path.join(MEDIA_DIR, file_name), "w", encoding="utf-8") as fp:
            fp.write(svg)
        count += 1
    print(f"Generated {count} Lucide SVG icons into {os.path.relpath(MEDIA_DIR, ROOT)}")


if __name__ == "__main__":
    sync_app_icon()
    sync_lucide_svgs()
