#!/usr/bin/env python3
"""Sprawdza, czy każde uprawnienie o protectionLevel 'privileged' żądane przez APK
w katalogach priv-app jest na allowliście privapp-permissions dla tego pakietu.
Z ro.control_privapp_permissions=enforce (domyślne w LineageOS) brak wpisu
dla aplikacji z obrazu = bootloop. Aktualizacje z Play są z tego sprawdzenia
wyłączone (isUpdatedSystemApp), więc liczy się wyłącznie wersja z obrazu.

Użycie: check-privapp.py <korzeń drzewa> <katalog proprietary>...
Każdy katalog jest przeszukiwany pod */priv-app/*/*.apk oraz */etc/permissions/*.xml.
"""
import glob, os, re, subprocess, sys

root = sys.argv[1]
dirs = sys.argv[2:] or ["vendor/gapps/common/proprietary", "vendor/gapps/arm64/proprietary"]
aapt2 = os.path.join(root, "prebuilts/sdk/tools/linux/bin/aapt2")
if not os.access(aapt2, os.X_OK):
    sys.exit(f"brak aapt2: {aapt2}")

# 1. zbiór uprawnień privileged z platformy
manifest = open(os.path.join(root, "frameworks/base/core/res/AndroidManifest.xml"), encoding="utf-8").read()
priv = set()
for m in re.finditer(r"<permission\b(.*?)/>", manifest, re.S):
    body = m.group(1)
    name = re.search(r'android:name="([^"]+)"', body)
    level = re.search(r'android:protectionLevel="([^"]+)"', body)
    if name and level and "privileged" in level.group(1):
        priv.add(name.group(1))

# 2. allowlisty (permission i deny-permission liczą się jako obsłużone)
allow = {}
for d in dirs:
    for f in glob.glob(os.path.join(root, d, "*/etc/permissions/*.xml")):
        x = open(f, encoding="utf-8").read()
        for m in re.finditer(r'<privapp-permissions\s+package="([^"]+)"\s*>(.*?)</privapp-permissions>', x, re.S):
            s = allow.setdefault(m.group(1), set())
            s.update(re.findall(r'<(?:deny-)?permission\s+name="([^"]+)"', m.group(2)))

# 3. APK w priv-app
apks = []
for d in dirs:
    apks += glob.glob(os.path.join(root, d, "*/priv-app/*/*.apk"))
if not apks:
    sys.exit("nie znaleziono żadnego APK w priv-app — złe ścieżki?")

bad = 0
seen = set()
for apk in sorted(apks):
    if os.path.basename(apk).startswith("split_"):
        continue  # splity dzielą manifest z base.apk
    pkg = subprocess.run([aapt2, "dump", "packagename", apk], capture_output=True, text=True).stdout.strip()
    out = subprocess.run([aapt2, "dump", "permissions", apk], capture_output=True, text=True).stdout
    req = set(re.findall(r"uses-permission(?:-sdk-23)?: name='([^']+)'", out))
    need = req & priv
    missing = sorted(need - allow.get(pkg, set()))
    seen.add(pkg)
    tag = "OK " if not missing else "BRAK"
    print(f"[{tag}] {pkg}  ({os.path.relpath(apk, root)})  privileged: {len(need)}")
    for p in missing:
        print(f"        - {p}")
    bad += len(missing)

if bad:
    sys.exit(f"\n{bad} brakujących uprawnień privileged — build zatrzymany, żeby nie było bootloopa.")
print(f"\nOK: {len(seen)} pakietów priv-app, allowlisty kompletne.")
