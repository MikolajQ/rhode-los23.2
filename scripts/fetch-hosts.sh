#!/usr/bin/env bash
# Generuje /system/etc/hosts dla obrazu: baza offline, której dziecko nie wyłączy bez roota.
# Zakres: adult (StevenBlack porn-only) + social (StevenBlack social-only) + komunikatory z lists/,
# minus lists/allow.txt (WhatsApp, Signal). Reklamy zostawiamy warstwie DNS (AdGuard DNS Family) —
# hosts jest liniowo przeszukiwany przy każdym zapytaniu, więc trzymamy go małym.
# Na telefonie tę samą warstwę rozwija AdAway (root z KernelSU-Next).
set -euo pipefail
ROOT=${1:?korzeń drzewa}
OUT="$ROOT/system/core/rootdir/etc/hosts"   # źródło modułu etc_hosts (AOSP); własny moduł dawał duplikat reguły w kati
RECIPE=$(cd "$(dirname "$0")/.." && pwd)
SB_COMMIT="b681eceec05a747aa409377d1b3aac0327916cff"   # StevenBlack/hosts, przypięty; podbijać razem z buildem
BASE="https://raw.githubusercontent.com/StevenBlack/hosts/$SB_COMMIT"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 "$BASE/alternates/porn-only/hosts"   > "$tmp/porn"
curl -fsSL --retry 3 "$BASE/alternates/social-only/hosts" > "$tmp/social"
{
  echo "# hosts wygenerowany przez rhode-los23.2/scripts/fetch-hosts.sh"
  echo "# StevenBlack/hosts @$SB_COMMIT (porn-only + social-only) + lists/communicators-block.txt - lists/allow.txt"
  echo "127.0.0.1 localhost"
  echo "::1 ip6-localhost"
  {
    cat "$tmp/porn" "$tmp/social" | grep -E '^0\.0\.0\.0 ' | awk '{print $2}'
    grep -vE '^\s*#|^\s*$' "$RECIPE/lists/communicators-block.txt"
  } | grep -vE '^(localhost|localhost\.localdomain|local|broadcasthost|ip6-.*|0\.0\.0\.0)$' \
    | grep -vEf <(grep -vE '^\s*#|^\s*$' "$RECIPE/lists/allow.txt") \
    | sort -u | sed 's/^/0.0.0.0 /'
} > "$OUT"
n=$(grep -c '^0\.0\.0\.0 ' "$OUT")
echo "hosts: $OUT — $n wpisów, $(du -k "$OUT" | cut -f1) KB"
if grep -E '(whatsapp\.(com|net)|whatsapp-cdn[^ ]*\.fbcdn\.net|signal\.(org|art))$' "$OUT"; then echo "BŁĄD: WhatsApp/Signal w hosts"; exit 1; fi
