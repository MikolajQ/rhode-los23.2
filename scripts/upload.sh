#!/usr/bin/env bash
# post_build: release na GitHubie + JSON dla Updatera.
# Serwer HAM kasuje się po sukcesie, więc to jedyna droga, którą wynik opuszcza chmurę.
set -euo pipefail
ROOT=${1:?korzeń drzewa}
REL_REPO=MikolajQ/rhode_releases
OUT="$ROOT/out/target/product/rhode"
export GH_TOKEN   # HAM ustawia go z argumentu gh_token
: "${GH_TOKEN:?brak GH_TOKEN}"

ZIP=$(ls -t "$OUT"/lineage-23.2-*-rhode*.zip | grep -v -- '-ota\|-img' | head -1)
[ -s "$ZIP" ] || { echo "brak zipa ROM-u w $OUT"; exit 1; }
NAME=$(basename "$ZIP")
TAG=$(echo "$NAME" | grep -oE '[0-9]{8}' | head -1)
UTC=$(grep -m1 '^ro.build.date.utc=' "$OUT/system/build.prop" | cut -d= -f2)

assets=("$ZIP")
# Build podpisany (sign.sh): obrazy z $OUT/signed-images - spójne z payload.bin. Build test-keys (mka bacon):
# $OUT/*.img. NIGDY z target_files_intermediates - to obrazy sprzed podpisu (stare otacerts, patrz sign.sh).
for img in boot dtbo vendor_boot; do
  if [ -s "$OUT/signed-images/$img.img" ]; then
    assets+=("$OUT/signed-images/$img.img")
  elif [ -s "$OUT/$img.img" ] && [ ! -s "$OUT/signed-target_files.zip" ]; then
    assets+=("$OUT/$img.img")
  else
    echo "brak spójnego $img.img (signed-images/) - nie publikuję niespójnych obrazów"; exit 1
  fi
done

# Zapis vmstat z całego builda (krok „vmstat w tle” w ham.yml) — jedyna kopia, serwer zaraz się kasuje.
if [ -s "$ROOT/vmstat.log" ]; then
  cp "$ROOT/vmstat.log" "$ROOT/vmstat-$TAG.log"
  assets+=("$ROOT/vmstat-$TAG.log")
fi

gh release create "$TAG" --repo "$REL_REPO" --title "lineage-23.2 $TAG rhode" \
  --notes "Build LineageOS lineage-23.2 + patche przepisu (w tym wybrane zmiany Tomoms) z $(date -u +%F). boot/dtbo/vendor_boot = obrazy z payload.bin (po podpisaniu): fastboot boot boot.img -> recovery -> Format data -> sideload." \
  "${assets[@]}"

# JSON dla Updatera — format opisany w README android_packages_apps_Updater (NetworkUpdate.kt):
# tablica (NIE {"response":[...]})  obiektów {datetime, files:[{filename,os_patch_level,os_sdk_level,
# ota_property_files,sha256,size,url}], type, version}. "type" porównywane z ro.lineage.releasetype,
# "version" z ro.lineage.build.version. 22.09: poprzedni format ({"response":[...]}, "romtype", "id"
# zamiast "sha256", brak files[]/os_sdk_level/ota_property_files) był ze STAREGO API Updatera — obecna
# apka (kotlinx.serialization) parsuje to inaczej i cicho nic nie pokazywała. os_sdk_level brakujące =
# domyślnie 0 w apce, co ZAWSZE odrzuca aktualizację (0 < bieżący SDK) - nie jest naprawdę opcjonalne
# mimo README. ota_property_files bierzemy z META-INF/com/android/metadata WEWNĄTRZ zipa (klucz
# ota-property-files=...) - to samo źródło, z którego bierzemy os_sdk_level/os_patch_level
# (post-sdk-level/post-security-patch-level), żeby nie mogły się rozjechać z prawdziwym payloadem.
METADATA=$(unzip -p "$ZIP" META-INF/com/android/metadata)
OTA_PROP_FILES=$(echo "$METADATA" | grep -m1 '^ota-property-files=' | cut -d= -f2- | sed 's/[[:space:]]*$//')
OS_SDK_LEVEL=$(echo "$METADATA" | grep -m1 '^post-sdk-level=' | cut -d= -f2)
OS_PATCH_LEVEL=$(echo "$METADATA" | grep -m1 '^post-security-patch-level=' | cut -d= -f2)
[ -n "$OTA_PROP_FILES" ] || { echo "brak ota-property-files w METADATA zipa"; exit 1; }
[ -n "$OS_SDK_LEVEL" ] || { echo "brak post-sdk-level w METADATA zipa"; exit 1; }

JSON=$(python3 - "$ZIP" "$TAG" "$REL_REPO" "$UTC" "$OTA_PROP_FILES" "$OS_SDK_LEVEL" "$OS_PATCH_LEVEL" <<'PY'
import hashlib, json, os, sys
zip_, tag, repo, utc, ota_prop_files, os_sdk_level, os_patch_level = sys.argv[1:8]
name = os.path.basename(zip_)
h = hashlib.sha256()
with open(zip_, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
print(json.dumps([{
    "datetime": int(utc),
    "files": [{
        "filename": name,
        "os_patch_level": os_patch_level,
        "os_sdk_level": int(os_sdk_level),
        "ota_property_files": ota_prop_files,
        "sha256": h.hexdigest(),
        "size": os.path.getsize(zip_),
        "url": f"https://github.com/{repo}/releases/download/{tag}/{name}",
    }],
    "type": "UNOFFICIAL",
    "version": "23.2",
}], indent=2))
PY
)
SHA=$(gh api "repos/$REL_REPO/contents/23.x/rhode.json" -q .sha 2>/dev/null || true)
gh api -X PUT "repos/$REL_REPO/contents/23.x/rhode.json" \
  -f message="rhode: $TAG" -f content="$(printf '%s\n' "$JSON" | base64 -w0)" ${SHA:+-f sha="$SHA"} >/dev/null
echo "release: https://github.com/$REL_REPO/releases/tag/$TAG"

# Serwer i wolumen kasuje ham-build z forka MikolajQ/ham po powrocie z post_build (odpina i kasuje wolumen,
# potem serwer). Kasowanie serwera stąd zabiłoby ham-build, zanim usunie wolumen (400 GB, ~28 €/mies.).
