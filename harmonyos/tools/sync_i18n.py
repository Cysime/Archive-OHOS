#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sync 12-language string resources from upstream Android `app/src/main/res/values-*/strings.xml`
into HarmonyOS `harmonyos/entry/src/main/resources/<locale>/element/string.json` without
modifying any upstream files.
"""
import json
import os
import re
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ANDROID_RES = os.path.join(ROOT, "app", "src", "main", "res")
OHOS_RES = os.path.join(ROOT, "harmonyos", "entry", "src", "main", "resources")

# Android values dir -> HarmonyOS resource qualifier directory
LOCALE_MAP = {
    "values": "base",
    "values-zh-rTW": "zh_TW",
    "values-en": "en_US",
    "values-ja": "ja_JP",
    "values-ko": "ko_KR",
    "values-de": "de_DE",
    "values-es": "es_ES",
    "values-fr": "fr_FR",
    "values-in": "id_ID",
    "values-ru": "ru_RU",
    "values-tr": "tr_TR",
    "values-ar": "ar_EG",
}

BASE_OHOS_STRINGS = [
    {"name": "module_desc", "value": "Archive HarmonyOS NEXT 客户端主模块"},
    {"name": "EntryAbility_desc", "value": "Archive 主界面"},
    {"name": "EntryAbility_label", "value": "Archive"},
]


def clean_android_text(text: str) -> str:
    if not text:
        return ""
    s = text.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n")
    # Convert Android printf positional formats %1$s / %1$d into HarmonyOS %s / %d compatible form
    s = re.sub(r"%\d+\$s", "%s", s)
    s = re.sub(r"%\d+\$d", "%d", s)
    return s.strip()


def sync_all() -> None:
    synced_locales = 0
    for android_dir, ohos_dir in LOCALE_MAP.items():
        xml_path = os.path.join(ANDROID_RES, android_dir, "strings.xml")
        if not os.path.exists(xml_path):
            continue
        tree = ET.parse(xml_path)
        root = tree.getroot()
        entries = list(BASE_OHOS_STRINGS)
        seen = {item["name"] for item in entries}
        for elem in root.findall("string"):
            name = elem.attrib.get("name", "").strip()
            if not name or name in seen or not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", name):
                continue
            raw_text = "".join(elem.itertext())
            entries.append({"name": name, "value": clean_android_text(raw_text)})
            seen.add(name)

        out_dir = os.path.join(OHOS_RES, ohos_dir, "element")
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, "string.json")
        with open(out_path, "w", encoding="utf-8") as fp:
            json.dump({"string": entries}, fp, ensure_ascii=False, indent=2)
            fp.write("\n")
        synced_locales += 1
        print(f"Synced {ohos_dir}: {len(entries)} strings")
    print(f"Total synced locales: {synced_locales}")


if __name__ == "__main__":
    sync_all()
