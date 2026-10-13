#!/usr/bin/env bash
# Po repo sync: żaden plik śledzony przez Git LFS nie może zostać wskaźnikiem (tekst „version
# https://git-lfs.github.com/spec/v1 …”, ~130 B) zamiast prawdziwej zawartości. Wskaźnik zamiast APK (GApps
# z GitLaba, WebView LineageOS) to błąd dopiero po godzinach builda albo zepsuty obraz. Projekty z LFS:
# .gitattributes z filter=lfs w katalogu projektu (+ vendor/gapps i external/chromium-webview zawsze).
# Brakujące obiekty: git lfs pull z ponowieniami; jeśli dalej brak — błąd.
# Użycie: check-lfs.sh <korzeń drzewa>   (LFS_RETRY_SLEEP — przerwa między próbami, domyślnie 60 s)
set -euo pipefail
ROOT=${1:?korzeń drzewa}
cd "$ROOT"
lfs=()
if command -v repo >/dev/null && [ -d .repo ]; then
  while read -r p; do
    if [ -f "$p/.gitattributes" ] && grep -q 'filter=lfs' "$p/.gitattributes"; then lfs+=("$p"); fi
  done < <(repo list -p)
fi
for p in vendor/gapps external/chromium-webview; do
  if [ -d "$p" ] && [[ " ${lfs[*]} " != *" $p "* ]]; then lfs+=("$p"); fi
done
pointers() {  # pliki LFS projektu $1, które są wskaźnikami
  git -C "$1" lfs ls-files -n 2>/dev/null | while read -r f; do
    if [ -f "$1/$f" ] && [ "$(stat -c %s "$1/$f")" -lt 1024 ] && head -c 64 "$1/$f" | grep -q '^version https://git-lfs'; then
      echo "$f"
    fi
  done
}
bad=0
for p in "${lfs[@]}"; do
  n=$(pointers "$p" | wc -l)
  [ "$n" -eq 0 ] && continue
  echo "[$p] $n plików LFS to wskaźniki — git lfs pull"
  for try in 1 2 3; do
    if git -C "$p" lfs pull && [ "$(pointers "$p" | wc -l)" -eq 0 ]; then break; fi
    [ "$try" = 3 ] || sleep $((try * ${LFS_RETRY_SLEEP:-60}))
  done
  n=$(pointers "$p" | wc -l)
  if [ "$n" -ne 0 ]; then echo "[$p] nadal $n wskaźników, np.:"; pointers "$p" | head -5; bad=1; fi
done
[ $bad -eq 0 ] && echo "LFS: ${#lfs[@]} projektów z LFS, wszystkie obiekty pobrane"
exit $bad
