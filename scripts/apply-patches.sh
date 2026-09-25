#!/usr/bin/env bash
# Nakłada patche z /ham-recipe/patches/<katalog> na odpowiadający projekt w drzewie.
# Nazwa katalogu = ścieżka projektu z '/' zamienionym na '_' (vendor_gapps -> vendor/gapps).
# Patch z nagłówkiem git format-patch ("From <sha> ...") idzie przez `git am -3` (commit z autorstwem
# oryginału, trójstronne scalanie, gdy LineageOS przesunie kontekst); zwykły diff przez `git apply`.
# Pierwszy patch, który nie wchodzi, zatrzymuje build — lepiej niż obraz bez części zmian.
set -euo pipefail
ROOT=${1:?korzeń drzewa}
RECIPE=$(cd "$(dirname "$0")/.." && pwd)
shopt -s nullglob
for dir in "$RECIPE"/patches/*/; do
  name=$(basename "$dir")
  proj=${name//_//}
  patches=("$dir"*.patch)
  [ ${#patches[@]} -gt 0 ] || { echo "[$name] brak patchy, pomijam"; continue; }
  [ -d "$ROOT/$proj" ] || { echo "[$name] brak projektu $proj w drzewie"; exit 1; }
  for p in "${patches[@]}"; do
    echo "[$name] $(basename "$p")"
    if head -1 "$p" | grep -q '^From [0-9a-f]\{40\} '; then
      git -C "$ROOT/$proj" -c user.name=ham -c user.email=ham@localhost am -3 --keep-cr -q "$p" || {
        git -C "$ROOT/$proj" am --abort || true
        echo "[$name] $(basename "$p") nie wchodzi na aktualny LineageOS — odśwież patch (scripts/check-patches.sh)"
        exit 1
      }
    else
      git -C "$ROOT/$proj" apply --check "$p"
      git -C "$ROOT/$proj" apply "$p"
    fi
  done
done
