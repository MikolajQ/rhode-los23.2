#!/usr/bin/env bash
# Świeżość WSZYSTKICH przypiętych źródeł przed `ham get` (wymaga zalogowanego gh).
# Tylko raportuje — nic nie aktualizuje automatycznie. Kernel/KSU-Next zwłaszcza NIE:
# to zmiana architektury hooków, nie prosty bump (patrz README/pamięć projektu, 22.09).
set -euo pipefail

echo "== 1) Patche przepisu vs aktualny LineageOS lineage-23.2 + scalenie jądra"
"$(dirname "$0")/check-patches.sh" || echo "  UWAGA: coś nie wejdzie — odświeżyć patch przed ham get (docs/przeglad-tomoms.md, sekcja o utrzymaniu)"
echo
echo "== 2) KernelSU-Next (legacy) — nasz pin vs upstream"
PINNED=$(gh api repos/MikolajQ/android_kernel_motorola_sm6225/commits/b2f4adb57 --jq '.commit.message' 2>/dev/null | head -1 | grep -oE 'legacy [0-9a-f]+' | awk '{print $2}' || echo "")
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
