#!/usr/bin/env bash
# Ile forki Tomoms w manifeście 16.2 odstają od LineageOS lineage-23.2.
# Uruchamiać lokalnie przed `ham get` (wymaga zalogowanego gh). Repa AOSP i LineageOS
# w manifeście są zawsze na tagu/HEAD, więc "rebase" dotyczy wyłącznie jego forków —
# a te odświeża tylko on. Opóźnienie > 30 dni = poczekać z buildem albo zaakceptować.
set -euo pipefail
MANIFEST_URL="https://raw.githubusercontent.com/tomoms/android/16.2/default.xml"
curl -sL "$MANIFEST_URL" | grep -oE 'name="Tomoms/[^"]+"' | sed 's/name="//;s/"//' | sort -u | while read -r name; do
  repo=${name#Tomoms/}
  th=$(gh api "repos/Tomoms/$repo/commits?sha=16.2&per_page=1" -q '.[0].commit.committer.date' 2>/dev/null || echo "")
  lh=$(gh api "repos/LineageOS/$repo/commits?sha=lineage-23.2&per_page=1" -q '.[0].commit.committer.date' 2>/dev/null || echo "")
  [[ "$th" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || th=""
  [[ "$lh" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || lh=""
  if [ -z "$lh" ]; then printf "%-46s Tomoms %s | LineageOS: brak forka (repo AOSP)\n" "$repo" "${th:0:10}"; continue; fi
  lag=$(( ( $(date -d "${lh:0:10}" +%s) - $(date -d "${th:0:10}" +%s) ) / 86400 ))
  [ "$lag" -lt 0 ] && lag=0
  printf "%-46s Tomoms %s | LineageOS %s | opóźnienie %3d dni %s\n" "$repo" "${th:0:10}" "${lh:0:10}" "$lag" "$([ "$lag" -gt 30 ] && echo '<-- >30 dni' || true)"
done
