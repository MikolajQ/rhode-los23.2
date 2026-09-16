#!/usr/bin/env bash
# Nakłada patche z /ham-recipe/patches/<katalog> na odpowiadający projekt w drzewie.
# Nazwa katalogu = ścieżka projektu z '/' zamienionym na '_' (vendor_gapps -> vendor/gapps).
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
    git -C "$ROOT/$proj" apply --check "$p"
    git -C "$ROOT/$proj" apply "$p"
  done
done
