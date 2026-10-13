#!/usr/bin/env bash
# post_build: wydanie na GitHubie + JSON dla Updatera. Wspólny dla przepisów a50s i rhode (urządzenie: device.env).
# Serwer HAM kasuje się po sukcesie, więc to jedyna droga, którą wynik opuszcza chmurę.
#
# Od 13.10 idempotentny i weryfikowany (wcześniej `gh release create <data>` padał, gdy wydanie z tą datą już
# istniało — drugi build tego samego dnia albo powtórka po urwanym uploadzie — i to po ~6 h builda):
# - tożsamość builda = sha256 zipa, zapisana w notatkach wydania. To samo wydanie (ten sam zip) -> dogrywane są
#   tylko brakujące pliki; inny build z tą samą datą -> tag <data>-2, -3...
# - każdy plik osobno, z ponowieniami; pliki już obecne z tą samą sumą są pomijane;
# - na końcu sumy SHA-256 policzone przez GitHub (REST: assets[].digest) porównywane z lokalnymi;
# - JSON dla Updatera dopiero po weryfikacji, więc telefon nigdy nie dostanie wskazania na niepełne wydanie.
# Do wydania idą też: przypięty manifest (repo manifest -r) i lista nałożonych patchy (.ham-patches) — da się
# dokładnie odtworzyć build, gdy coś wyjdzie dopiero na telefonie.
# Test bez prawdziwego builda: OUT=<katalog> UPLOAD_REPO=<repo> UPLOAD_JSON=<ścieżka> upload.sh <korzeń>.
set -euo pipefail
D=$(dirname "$0")
source "$D/device.env"
ROOT=${1:?korzeń drzewa}
REL_REPO=${UPLOAD_REPO:-$REL_REPO}
JSON_PATH=${UPLOAD_JSON:-23.x/$DEVICE.json}
OUT=${OUT:-$ROOT/out/target/product/$DEVICE}
export GH_TOKEN   # HAM ustawia go z argumentu gh_token
: "${GH_TOKEN:?brak GH_TOKEN}"
MAX=2147483647    # limit GitHuba: każdy plik wydania < 2 GiB

ZIP=$(ls -t "$OUT"/lineage-23.2-*-"$DEVICE"*.zip | grep -v -- '-ota\|-img' | head -1)
[ -s "$ZIP" ] || { echo "brak zipa ROM-u w $OUT"; exit 1; }
NAME=$(basename "$ZIP")
DATE=$(echo "$NAME" | grep -oE '[0-9]{8}' | head -1)
UTC=$(grep -m1 '^ro.build.date.utc=' "$OUT/system/build.prop" | cut -d= -f2)
ZIP_SHA=$(sha256sum "$ZIP" | cut -d' ' -f1)

# --- tag: to samo wydanie (ten sam zip) albo pierwszy wolny <data>[-N]
TAG=$DATE; n=1; STATE=""
while [ -z "$STATE" ]; do
  if body=$(gh api "repos/$REL_REPO/releases/tags/$TAG" --jq .body 2>"$OUT/.gh-err"); then
    if grep -q "$ZIP_SHA" <<< "$body"; then STATE=same; else n=$((n + 1)); TAG="$DATE-$n"; fi
  elif grep -q 'Not Found\|HTTP 404' "$OUT/.gh-err"; then
    STATE=new
  else
    cat "$OUT/.gh-err"; echo "nie mogę sprawdzić wydania $TAG (sieć/token?)"; exit 1
  fi
done
echo "wydanie: $TAG ($([ "$STATE" = same ] && echo 'ten sam build — dogrywam brakujące' || echo nowe))"

# --- pliki
assets=("$ZIP")
# Build podpisany (sign.sh): obrazy z $OUT/signed-images - spójne z zipem. Build test-keys (mka bacon):
# $OUT/*.img. NIGDY z target_files_intermediates - to obrazy sprzed podpisu (stare otacerts, patrz sign.sh).
for img in $RELEASE_IMAGES; do
  if [ -s "$OUT/signed-images/$img.img" ]; then
    assets+=("$OUT/signed-images/$img.img")
  elif [ -s "$OUT/$img.img" ] && [ ! -s "$OUT/signed-target_files.zip" ]; then
    assets+=("$OUT/$img.img")
  else
    echo "brak spójnego $img.img (signed-images/) - nie publikuję niespójnych obrazów"; exit 1
  fi
done
# np. dtb A50s: osobna partycja, poza IMAGES/ target-files, bez otacerts — wersja z $OUT jest spójna
for img in $EXTRA_IMAGES; do [ -s "$OUT/$img.img" ] && assets+=("$OUT/$img.img"); done
# vmstat z całego builda (krok „vmstat w tle”) — jedyna kopia, serwer zaraz się kasuje
[ -s "$ROOT/vmstat.log" ] && cp "$ROOT/vmstat.log" "$OUT/vmstat-$TAG.log" && assets+=("$OUT/vmstat-$TAG.log")
# przypięty manifest i lista patchy: odtworzenie dokładnie tego builda
if (cd "$ROOT" && repo manifest -r -o "$OUT/manifest-$TAG.xml" 2>/dev/null) && [ -s "$OUT/manifest-$TAG.xml" ]; then
  assets+=("$OUT/manifest-$TAG.xml")
else
  echo "UWAGA: repo manifest -r nie wyszedł — wydanie bez przypiętego manifestu"
fi
if compgen -G "$ROOT/.ham-patches/*.tsv" >/dev/null; then
  for t in "$ROOT"/.ham-patches/*.tsv; do
    p=$(basename "$t" .tsv); while IFS=$'\t' read -r id c f; do printf '%s\t%s\t%s\t%s\n' "${p//_//}" "$f" "$id" "$c"; done < "$t"
  done > "$OUT/patches-$TAG.txt"
  assets+=("$OUT/patches-$TAG.txt")
fi
for a in "${assets[@]}"; do
  [ "$(stat -c %s "$a")" -le $MAX ] || { echo "$(basename "$a"): ponad 2 GiB — GitHub go nie przyjmie"; exit 1; }
done

# --- wydanie i upload
if [ "$STATE" = new ]; then
  gh release create "$TAG" --repo "$REL_REPO" --title "lineage-23.2 $TAG $DEVICE" \
    --notes "Build LineageOS lineage-23.2 + patche przepisu z $(date -u +%F). $RELEASE_NOTES
zip sha256: $ZIP_SHA"
fi
remote() { gh api "repos/$REL_REPO/releases/tags/$TAG" --jq '.assets[] | "\(.name) \(.digest)"'; }
have=$(remote)
for a in "${assets[@]}"; do
  n=$(basename "$a"); s=$(sha256sum "$a" | cut -d' ' -f1)
  if grep -qxF "$n sha256:$s" <<< "$have"; then echo "  $n: już jest"; continue; fi
  for try in 1 2 3 4 5; do
    echo "  $n: upload (próba $try)"
    gh release upload "$TAG" "$a" --repo "$REL_REPO" --clobber && break
    [ "$try" = 5 ] && { echo "$n: upload nieudany 5 razy"; exit 1; }
    sleep $((try * 30))
  done
done

# --- weryfikacja: sumy policzone przez GitHub = lokalne
have=$(remote)
for a in "${assets[@]}"; do
  n=$(basename "$a"); s=$(sha256sum "$a" | cut -d' ' -f1)
  if grep -qxF "$n sha256:$s" <<< "$have"; then continue; fi
  if grep -qxF "$n null" <<< "$have"; then echo "  UWAGA: GitHub nie podał sumy $n (sprawdzam tylko obecność)"; continue; fi
  echo "$n: w wydaniu brak albo inna suma niż lokalna"; exit 1
done
echo "wydanie $TAG: ${#assets[@]} plików, sumy zgodne z lokalnymi"

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

JSON=$(python3 - "$ZIP" "$TAG" "$REL_REPO" "$UTC" "$OTA_PROP_FILES" "$OS_SDK_LEVEL" "$OS_PATCH_LEVEL" "$ZIP_SHA" <<'PY'
import json, os, sys
zip_, tag, repo, utc, ota_prop_files, os_sdk_level, os_patch_level, sha = sys.argv[1:9]
name = os.path.basename(zip_)
print(json.dumps([{
    "datetime": int(utc),
    "files": [{
        "filename": name,
        "os_patch_level": os_patch_level,
        "os_sdk_level": int(os_sdk_level),
        "ota_property_files": ota_prop_files,
        "sha256": sha,
        "size": os.path.getsize(zip_),
        "url": f"https://github.com/{repo}/releases/download/{tag}/{name}",
    }],
    "type": "UNOFFICIAL",
    "version": "23.2",
}], indent=2))
PY
)
SHA=$(gh api "repos/$REL_REPO/contents/$JSON_PATH" -q .sha 2>/dev/null || true)
gh api -X PUT "repos/$REL_REPO/contents/$JSON_PATH" \
  -f message="$DEVICE: $TAG" -f content="$(printf '%s\n' "$JSON" | base64 -w0)" ${SHA:+-f sha="$SHA"} >/dev/null
echo "release: https://github.com/$REL_REPO/releases/tag/$TAG"
bash "$D/notify.sh" "Build $DEVICE gotowy" "Wydanie $TAG: https://github.com/$REL_REPO/releases/tag/$TAG" || true

# Serwer i wolumen kasuje ham-build z forka MikolajQ/ham po powrocie z post_build (odpina i kasuje wolumen,
# potem serwer). Kasowanie serwera stąd zabiłoby ham-build, zanim usunie wolumen (400 GB, ~28 €/mies.).
