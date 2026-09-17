#!/usr/bin/env bash
# Kontrola statyczna gotowego zipa OTA przed flashem — na tej maszynie, bez roota.
# Sprawdza to, czego nie da się zobaczyć w emulatorze (obraz rhode na nim nie wstanie):
# czy w obrazie jest wszystko, co build miał dodać, i nic z tego, co miał wyciąć.
#
# Użycie: inspect-zip.sh lineage-23.2-YYYYMMDD-UNOFFICIAL-rhode.zip [katalog-roboczy]
# Wymaga: unzip, debugfs (e2fsprogs), payload-dumper-go (https://github.com/ssut/payload-dumper-go/releases
# — binarka do ~/bin; obrazy rhode są ext4, więc debugfs wystarcza do czytania).
set -uo pipefail
ZIP=${1:?zip OTA}
WORK=${2:-"${XDG_CACHE_HOME:-$HOME/.cache}/rhode-inspect/$(basename "$ZIP" .zip)"}
pass=0; fail=0; warn=0
ok()   { printf '  \033[32mOK  \033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; warn=$((warn+1)); }
need() { command -v "$1" >/dev/null || { echo "brak narzędzia: $1 — $2"; exit 2; }; }
need unzip "pacman -S unzip"; need debugfs "pacman -S e2fsprogs"
need payload-dumper-go "binarka z https://github.com/ssut/payload-dumper-go/releases do ~/bin"

mkdir -p "$WORK"; cd "$WORK"
echo "== zip: $ZIP"
unzip -l "$ZIP" | grep -qE ' payload\.bin$' && ok "payload.bin (A/B OTA)" || { bad "brak payload.bin — to nie jest zip OTA A/B"; exit 1; }
unzip -l "$ZIP" | grep -qE 'META-INF/com/android/metadata' && ok "metadata OTA" || warn "brak META-INF/com/android/metadata"
unzip -o -q "$ZIP" payload.bin payload_properties.txt META-INF/com/android/metadata -d . 2>/dev/null
grep -E 'pre-device|post-timestamp|post-build' META-INF/com/android/metadata 2>/dev/null | sed 's/^/     /'
grep -q 'pre-device=rhode' META-INF/com/android/metadata 2>/dev/null && ok "pre-device=rhode" || bad "metadata nie mówi pre-device=rhode"

echo "== wyciągam partycje (system, system_ext, product, boot)"
[ -s system.img ] || payload-dumper-go -p system,system_ext,product,boot -o . payload.bin >/dev/null 2>&1
for p in system system_ext product boot; do [ -s "$p.img" ] && ok "$p.img $(du -m "$p.img" | cut -f1) MB" || bad "brak $p.img w payload"; done

# --- pomocnicze: debugfs bez roota; system.img ma korzeń "/" z katalogiem /system (system-as-root)
dcat() { debugfs -R "cat $2" "$1" 2>/dev/null; }
dls()  { debugfs -R "ls -p $2" "$1" 2>/dev/null | awk -F/ 'NF>5 {print $6}' | grep -vE '^\.\.?$|^$'; }
dhas() { dls "$1" "$(dirname "$2")" | grep -qxF "$(basename "$2")"; }
sysp() { dhas system.img "/system$1" && echo "/system$1" || echo "$1"; }   # /system/x albo /x

echo "== system"
HOSTS=$(sysp /etc/hosts); n=$(dcat system.img "$HOSTS" | grep -c '^0\.0\.0\.0 ')
[ "$n" -ge 50000 ] && ok "hosts: $n wpisów" || bad "hosts: $n wpisów (oczekiwane ≥ 50000) — fetch-hosts.sh nie zadziałał albo PRODUCT_COPY_FILES przegrał z system/core"
dcat system.img "$HOSTS" | grep -qE '(whatsapp\.(com|net)|whatsapp-cdn[^ ]*\.fbcdn\.net|signal\.org)$' && bad "hosts blokuje WhatsApp/Signal" || ok "hosts: WhatsApp i Signal wolne"
dcat system.img "$HOSTS" | grep -qE ' www\.instagram\.com$' && ok "hosts: Instagram zablokowany" || warn "hosts: brak www.instagram.com — lista social nie weszła?"
BP=$(sysp /build.prop); dcat system.img "$BP" | grep -E '^ro\.build\.(version\.release|version\.security_patch|date\.utc|version\.incremental)=' | sed 's/^/     /'
dcat system.img "$BP" | grep -q '^ro.build.version.release=16' && ok "Android 16" || bad "to nie Android 16"
FDR=$(sysp /etc/org.fdroid.fdroid/additional_repos.xml)
dcat system.img "$FDR" | grep -q 'izzysoft' && ok "F-Droid additional_repos.xml (IzzyOnDroid)" || warn "brak additional_repos.xml z IzzyOnDroid (ścieżka $FDR)"

echo "== system_ext"
dcat system_ext.img /etc/build.prop | grep -q 'lineage.updater.uri=.*MikolajQ/rhode_releases' && ok "OTA wskazuje na rhode_releases" || bad "lineage.updater.uri nie wskazuje na MikolajQ/rhode_releases (Updater podsunąłby buildy Tomoms)"

echo "== product: GApps i dodatki"
for d in GmsCore Phonesky GmsSupervision Gearhead; do dls product.img /priv-app | grep -qx "$d" && ok "priv-app/$d" || bad "brak priv-app/$d"; done
n=$(dls product.img /priv-app/GmsSupervision | grep -c '\.apk$'); [ "$n" -eq 1 ] && ok "GmsSupervision: jeden APK (nodpi)" || bad "GmsSupervision: $n plików .apk (oczekiwany 1)"
for d in Velvet VelvetTitan AndroidAutoStub GoogleRestore Wellbeing; do dls product.img /priv-app | grep -qx "$d" && bad "priv-app/$d — miało być wycięte patchem MTG" || ok "brak $d (wycięte)"; done
for d in Bellis LogViewer; do { dls product.img /app; dls product.img /priv-app; dls system.img /system/app; dls system.img /system/priv-app; } | grep -qx "$d" && bad "$d w obrazie" || ok "brak $d"; done
dcat product.img /etc/permissions/privapp-permissions-google-product.xml | grep -q 'com.google.android.gms.supervision' && ok "allowlist gms.supervision" || bad "brak bloku gms.supervision w privapp-permissions-google-product.xml"
dls product.img /etc/permissions | grep -qi gearhead && ok "allowlist Gearhead" || bad "brak privapp-permissions dla Gearhead"
dls product.img /etc/sysconfig | grep -q 'google.xml' && ok "sysconfig google.xml (allow-in-power-save dla GMS)" || bad "brak sysconfig/google.xml — push i Family Link umrą w Doze"
{ dls product.img /app; dls product.img /priv-app; } | grep -qiE 'webview|cromite' && ok "WebView w product: $({ dls product.img /app; dls product.img /priv-app; } | grep -iE 'webview|cromite' | tr '\n' ' ')" || bad "brak modułu WebView w product"
{ dls product.img /app; dls system.img /system/app; } | grep -qx 'F-Droid' && ok "F-Droid" || warn "brak F-Droid w app/"

echo "== boot.img"
if strings boot.img | grep -q 'KernelSU'; then ok "boot.img: ślady KernelSU w jądrze"; else warn "boot.img: brak stringów KernelSU (Image.gz? sprawdź: unpack + strings)"; fi
strings boot.img | grep -m1 -oE 'Linux version 4\.19\.[0-9]+[^ ]*' | sed 's/^/     /'

echo
echo "== podsumowanie: $pass OK, $warn WARN, $fail FAIL  (robocze pliki: $WORK)"
[ "$fail" -eq 0 ] && echo "   zip nadaje się do sideloadu na nieaktywny slot" || echo "   NIE flashować — najpierw FAIL-e"
exit $(( fail > 0 ))
