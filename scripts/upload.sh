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

gh release create "$TAG" --repo "$REL_REPO" --title "lineage-23.2 $TAG rhode" \
  --notes "Build z manifestu Tomoms 16.2 z $(date -u +%F). boot/dtbo/vendor_boot = obrazy z payload.bin (po podpisaniu): fastboot boot boot.img -> recovery -> Format data -> sideload." \
  "${assets[@]}"

# JSON dla Updatera (format jak Tomoms/ota_provider); datetime = ro.build.date.utc, bo Updater
# porównuje go z bieżącym buildem.
JSON=$(python3 - "$ZIP" "$TAG" "$REL_REPO" "$UTC" <<'PY'
import hashlib, json, os, sys
zip_, tag, repo, utc = sys.argv[1:5]
name = os.path.basename(zip_)
h = hashlib.sha1()
with open(zip_, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
print(json.dumps({"response": [{
    "datetime": int(utc), "filename": name, "id": h.hexdigest(), "romtype": "UNOFFICIAL",
    "size": os.path.getsize(zip_),
    "url": f"https://github.com/{repo}/releases/download/{tag}/{name}", "version": "23.2"}]}, indent=2))
PY
)
SHA=$(gh api "repos/$REL_REPO/contents/23.x/rhode.json" -q .sha 2>/dev/null || true)
gh api -X PUT "repos/$REL_REPO/contents/23.x/rhode.json" \
  -f message="rhode: $TAG" -f content="$(printf '%s\n' "$JSON" | base64 -w0)" ${SHA:+-f sha="$SHA"} >/dev/null
echo "release: https://github.com/$REL_REPO/releases/tag/$TAG"
