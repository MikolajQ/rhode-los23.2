#!/usr/bin/env bash
# Świeżość WSZYSTKICH przypiętych źródeł przed `ham get` (wymaga zalogowanego gh).
# Tylko raportuje — nic nie aktualizuje automatycznie. Kernel/KSU-Next zwłaszcza NIE:
# to zmiana architektury hooków, nie prosty bump (patrz README/pamięć projektu, 22.09).
set -euo pipefail

echo "== 1) Forki Tomoms w manifeście 16.2 vs LineageOS lineage-23.2"
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

echo
echo "== 2) KernelSU-Next (legacy) — nasz pin vs upstream"
PINNED=$(gh api repos/MikolajQ/android_kernel_motorola_sm6225/commits/7108db17f --jq '.commit.message' 2>/dev/null | grep -oE '[0-9a-f]{10}' | head -1 || echo "")
if [ -n "$PINNED" ]; then
  UPSTREAM=$(gh api repos/KernelSU-Next/KernelSU-Next/branches/legacy --jq '.commit.sha[0:10]')
  N=$(gh api "repos/KernelSU-Next/KernelSU-Next/compare/$PINNED...legacy" --jq '.total_commits' 2>/dev/null || echo "?")
  echo "pin $PINNED -> legacy HEAD $UPSTREAM ($N commitów w tyle)"
  [ "$N" != "0" ] && [ "$N" != "?" ] && echo "  UWAGA: sprawdzić diff ręcznie (gh api repos/KernelSU-Next/KernelSU-Next/compare/$PINNED...legacy), nie mergować bezmyślnie — patrz notatka 22.09 o reorganizacji kernel/hook"
else
  echo "nie znaleziono pinu w commit 7108db17f — sprawdzić ręcznie"
fi

echo
echo "== 3) Droid-ify — nasz pin vs latest release"
DPIN=$(grep -oE 'TAG="v[0-9.]+"' scripts/fetch-droidify.sh | grep -oE 'v[0-9.]+')
DLATEST=$(gh api repos/Droid-ify/client/releases/latest --jq '.tag_name')
echo "pin $DPIN -> latest $DLATEST$([ "$DPIN" != "$DLATEST" ] && echo '  <-- podbić TAG+SHA256 w fetch-droidify.sh')"

echo
echo "== 4) fork ham @noble vs upstream antony-jr/ham (informacyjnie — mocno załatany, nie auto-merge)"
gh api repos/MikolajQ/ham/branches/noble --jq '"nasz HEAD: " + .commit.sha[0:10] + " (" + .commit.commit.author.date[0:10] + ")"' 2>/dev/null || true
gh api repos/antony-jr/ham/commits --jq '.[0] | "upstream HEAD: " + .sha[0:10] + " (" + .commit.author.date[0:10] + ")"' 2>/dev/null || true
