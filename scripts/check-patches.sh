#!/usr/bin/env bash
# Lokalnie, przed `ham get`: czy patches/* wchodzą na AKTUALNE gałęzie LineageOS i czy jądro (nasz fork
# 16.2-ksun) scala się z LineageOS lineage-23.2 bez konfliktu — to samo, co zrobią kroki w ham.yml na serwerze,
# ale w kilka minut i bez pobierania źródeł (klony bez plików w ~/.cache/rhode-check-patches, git apply --cached).
# Nic nie zmienia w przepisie. Kod wyjścia 1 = coś nie wejdzie, build padłby na serwerze.
set -uo pipefail
RECIPE=$(cd "$(dirname "$0")/.." && pwd)
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/rhode-check-patches
mkdir -p "$CACHE"
LOS=https://raw.githubusercontent.com/LineageOS/android/lineage-23.2

# ścieżka projektu -> "url<TAB>gałąź/tag" z manifestu LineageOS + rhode.xml (rhode.xml wygrywa)
MAP=$(python3 - "$RECIPE/rhode.xml" "$LOS" <<'PY'
import sys, urllib.request, xml.etree.ElementTree as ET
local, base = sys.argv[1], sys.argv[2]
def parse(root, remotes, default):
    for r in root.iter('remote'):
        f = r.get('fetch')
        remotes[r.get('name')] = ('https://github.com/' if f == '..' else f.rstrip('/') + '/', r.get('revision'))
    for d in root.iter('default'):
        default.update({k: v for k, v in d.attrib.items()})
    out = {}
    for p in root.iter('project'):
        rem = p.get('remote') or default.get('remote')
        url, rrev = remotes[rem]
        rev = p.get('revision') or rrev or default.get('revision')
        out[p.get('path') or p.get('name')] = (url + p.get('name'), rev.replace('refs/heads/', ''))
    return out
remotes, default, projects = {}, {}, {}
for f in ('default.xml', 'snippets/lineage.xml'):
    projects.update(parse(ET.fromstring(urllib.request.urlopen(f'{base}/{f}').read()), remotes, default))
projects.update(parse(ET.parse(local).getroot(), remotes, default))
for path, (url, rev) in projects.items():
    print(f'{path}\t{url}\t{rev}')
PY
) || { echo "nie udało się pobrać manifestu LineageOS"; exit 1; }

fail=0
shopt -s nullglob
for dir in "$RECIPE"/patches/*/; do
  name=$(basename "$dir"); proj=${name//_//}
  patches=("$dir"*.patch); [ ${#patches[@]} -gt 0 ] || continue
  line=$(awk -F'\t' -v p="$proj" '$1==p' <<<"$MAP")
  [ -n "$line" ] || { echo "[$name] projekt $proj nie istnieje w manifeście"; fail=1; continue; }
  url=$(cut -f2 <<<"$line"); rev=$(cut -f3 <<<"$line")
  repo="$CACHE/$name.git"
  [ -d "$repo" ] || git init -q --bare "$repo"
  git -C "$repo" config remote.origin.url "$url"
  git -C "$repo" config remote.origin.promisor true
  git -C "$repo" config remote.origin.partialclonefilter blob:none
  if ! git -C "$repo" fetch -q --filter=blob:none --depth=1 origin "$rev" 2>/dev/null; then
    echo "[$name] nie można pobrać $url @ $rev"; fail=1; continue
  fi
  idx=$(mktemp -u); export GIT_INDEX_FILE=$idx
  git -C "$repo" read-tree FETCH_HEAD
  bad=""
  for p in "${patches[@]}"; do
    git -C "$repo" apply --cached "$p" 2>/dev/null || git -C "$repo" apply --cached --3way "$p" >/dev/null 2>&1 || { bad=$(basename "$p"); break; }
  done
  unset GIT_INDEX_FILE; rm -f "$idx"
  if [ -n "$bad" ]; then
    echo "[$name] NIE WCHODZI: $bad  (upstream $(git -C "$repo" rev-parse --short FETCH_HEAD))"; fail=1
  else
    echo "[$name] OK, ${#patches[@]} patchy (upstream $(git -C "$repo" rev-parse --short FETCH_HEAD))"
  fi
done

# jądro: to samo co krok „Jądro: scalenie z LineageOS lineage-23.2” w ham.yml
k="$CACHE/kernel.git"
[ -d "$k" ] || git init -q --bare "$k"
for r in our:MikolajQ:16.2-ksun los:LineageOS:lineage-23.2; do
  IFS=: read -r n owner br <<<"$r"
  git -C "$k" config "remote.$n.url" "https://github.com/$owner/android_kernel_motorola_sm6225"
  git -C "$k" config "remote.$n.promisor" true
  git -C "$k" fetch -q --filter=blob:none --shallow-since=2026-01-01 "$n" "+$br:refs/$n" 2>/dev/null || { echo "[jądro] nie można pobrać $owner $br"; fail=1; }
done
behind=$(git -C "$k" rev-list --count refs/our..refs/los 2>/dev/null)
if git -C "$k" merge-tree --write-tree refs/our refs/los >/dev/null 2>&1; then
  echo "[jądro] OK, scalenie czyste ($behind commitów LineageOS do dociągnięcia)"
else
  echo "[jądro] KONFLIKT przy scalaniu z LineageOS ($behind commitów) — rozwiązać w forku 16.2-ksun przed buildem"; fail=1
fi
exit $fail
