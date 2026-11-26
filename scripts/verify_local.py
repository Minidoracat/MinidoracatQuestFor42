# -*- coding: utf-8 -*-
"""Quest 專屬的靜態檢查：scripts/verify_mod.py 第 19 項會呼叫；單獨跑 `python scripts/verify_local.py`。
從換成家族模板前的 verify_mod.py 原樣搬來（模板沒有）：
  - 稱號在同一語言不重複 — IGUI_MQ_Title_* 的值：玩家在頭上、聊天、排行榜只看到稱號，同名就分不出是哪個成就給的
                          （2026-10-26 查到 7 組，例如 CH「誘捕大師」同時是誘捕技能與陷阱收穫的稱號）
"""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

passed, failed = [], []

# 豁免清單與 verify_mod.py 共用：scripts/verify_ignore.txt，每行一個子字串樣式（# 開頭為註解）。
IGNORE_PATTERNS = []
_ign = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verify_ignore.txt")
if os.path.isfile(_ign):
    with open(_ign, encoding="utf-8") as _fh:
        for _line in _fh:
            _line = _line.strip()
            if _line and not _line.startswith("#"):
                IGNORE_PATTERNS.append(_line)


def ok(label):
    passed.append(label)
    print(f"  PASS  {label}")


def fail(label, details=None):
    if not details:  # 說失敗卻沒附細節（例：子程序結束碼非零但沒輸出）也是失敗；空清單走下面會記成 PASS
        failed.append(label)
        print(f"  FAIL  {label}")
        return
    kept = [d for d in details if not any(p in d for p in IGNORE_PATTERNS)]
    waived = [d for d in details if any(p in d for p in IGNORE_PATTERNS)]
    for d in waived:
        print(f"  WAIVE {label}: {d}（verify_ignore.txt 豁免）")
    if not kept:
        if waived:
            ok(f"{label}（{len(waived)} 筆豁免）")
        else:
            ok(label)
        return
    failed.append(label)
    print(f"  FAIL  {label}")
    for d in kept:
        print(f"        {d}")


def find_media():
    hits = []
    mod_root = os.path.join(REPO, "MOD")
    if os.path.isdir(mod_root):
        for folder in os.listdir(mod_root):
            p = os.path.join(mod_root, folder, "Contents", "mods")
            if not os.path.isdir(p):
                continue
            for inner in os.listdir(p):
                media = os.path.join(p, inner, "42", "media")
                if os.path.isdir(media):
                    hits.append(media)
    return hits


def iter_files(root, exts):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git",)]
        for name in files:
            if os.path.splitext(name)[1] in exts:
                yield os.path.join(base, name)


MEDIA_DIRS = find_media()
if not MEDIA_DIRS:
    print("找不到 MOD/*/Contents/mods/*/42/media，中止")
    sys.exit(2)

# ---- 稱號在同一語言不重複（見檔頭）----
for m in MEDIA_DIRS:
    troot = os.path.join(m, "lua", "shared", "Translate")
    if not os.path.isdir(troot):
        continue
    langs = sorted(d for d in os.listdir(troot) if os.path.isdir(os.path.join(troot, d)))
    dup_titles = []
    for l in langs:
        p = os.path.join(troot, l, "IG_UI.json")
        try:
            with open(p, encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception:
            continue  # 缺檔與解析失敗由 verify_mod.py 的翻譯檢查回報
        by_name = {}
        for k, v in data.items():
            if k.startswith("IGUI_MQ_Title_") and isinstance(v, str):
                by_name.setdefault(v.strip().casefold(), []).append(k)
        dup_titles += [f"{l}: {'、'.join(ks)} 都是「{data[ks[0]]}」" for ks in by_name.values() if len(ks) > 1]
    fail("稱號在同一語言不重複", dup_titles) if dup_titles else ok("稱號在同一語言不重複")

sys.exit(1 if failed else 0)
