#!/usr/bin/env bash
# Nakłada patche z /ham-recipe/patches/<katalog> na odpowiadający projekt w drzewie.
# Nazwa katalogu = ścieżka projektu z '/' zamienionym na '_' (vendor_gapps -> vendor/gapps).
# Patch z nagłówkiem git format-patch ("From <sha> ...") idzie przez `git am -3` (commit z autorstwem
# oryginału, trójstronne scalanie, gdy LineageOS przesunie kontekst); zwykły diff przez `git apply`.
# Pierwszy patch, który nie wchodzi, zatrzymuje build — lepiej niż obraz bez części zmian.
#
# To jest SYNCHRONIZACJA drzewa z przepisem, nie tylko nakładanie (od 13.10). Stan w $ROOT/.ham-patches/:
# <katalog>.tsv = „patch-id<TAB>commit|-<TAB>nazwa” dla każdego nałożonego patcha, a kopie nałożonych
# diffów w <katalog>/<suma>.patch. Ponowne uruchomienie na zachowanym serwerze (krok „Patche” albo
# ham-resume.sh -r) cofa patche usunięte z przepisu albo zmienione (inny patch-id: git revert / git apply -R)
# i nakłada nowe. Wcześniej nałożone rozpoznawał po temacie commita, więc patch poprawiony pod tym samym
# tytułem albo usunięty i dodany z powrotem był po cichu pomijany, a usunięty — zostawał w drzewie.
# Wpis stanu, którego zmiany w drzewie już nie ma (np. repo sync cofnął projekt), jest pomijany i patch
# nakładany od nowa. Cofnięcie, które koliduje z późniejszymi patchami, zatrzymuje skrypt (do ręcznego
# rozwiązania na serwerze). Drzewo bez stanu, ale z patchami nałożonymi starą wersją skryptu: stan jest
# odtwarzany po temacie commita (format-patch) i próbie odwrócenia (diff).
set -euo pipefail
ROOT=${1:?korzeń drzewa}
RECIPE=$(cd "$(dirname "$0")/.." && pwd)
STATE="$ROOT/.ham-patches"
mkdir -p "$STATE"
shopt -s nullglob

G() { git -C "$ROOT/$proj" -c user.name=ham -c user.email=ham@localhost "$@"; }
# Klucz patcha = git patch-id (sama treść zmiany): ponowny eksport z innym nagłówkiem (hash, data) to nadal
# ten sam patch, więc nie jest cofany i nakładany od nowa. sha256 pliku tylko, gdy patch-id nic nie zwróci.
sum() { local id; id=$(git patch-id --stable < "$1" 2>/dev/null | awk 'NR==1 {print $1}')
        [ -n "$id" ] && echo "$id" || sha256sum "$1" | cut -d' ' -f1; }
is_fp() { head -1 "$1" | grep -q '^From [0-9a-f]\{40\} '; }
# czy zmiana z wpisu stanu nadal jest w drzewie
present() {  # $1 commit|-  $2 suma
  if [ "$1" = - ]; then git -C "$ROOT/$proj" apply --reverse --check "$STATE/$name/$2.patch" 2>/dev/null
  else git -C "$ROOT/$proj" merge-base --is-ancestor "$1" HEAD 2>/dev/null && ! reverted "$1"; fi
}
# commit cofnięty później przez git revert (np. ręcznie na serwerze) — jego zmiany w drzewie nie ma
reverted() { git -C "$ROOT/$proj" log --format=%B "$1..HEAD" | grep -q "This reverts commit $1"; }

names=()
for d in "$RECIPE"/patches/*/; do names+=("$(basename "$d")"); done
for f in "$STATE"/*.tsv; do
  n=$(basename "$f" .tsv)
  [ -d "$RECIPE/patches/$n" ] || names+=("$n")   # projekt usunięty z przepisu: cofnąć, co zostało
done

for name in "${names[@]}"; do
  proj=${name//_//}
  st="$STATE/$name.tsv"
  patches=("$RECIPE/patches/$name/"*.patch)
  if [ ! -d "$ROOT/$proj" ]; then
    [ ${#patches[@]} -eq 0 ] && continue
    echo "[$name] brak projektu $proj w drzewie"; exit 1
  fi
  mkdir -p "$STATE/$name"; touch "$st"

  declare -A want=()
  for p in "${patches[@]}"; do want[$(sum "$p")]=$p; done

  # 0) stan sprzed tej wersji skryptu: odtworzyć z drzewa
  if [ ! -s "$st" ]; then
    for p in "${patches[@]}"; do
      s=$(sum "$p")
      if is_fp "$p"; then
        subj=$(git mailinfo /dev/null /dev/null < "$p" 2>/dev/null | sed -n 's/^Subject: //p')
        c=$(git -C "$ROOT/$proj" log -n 300 --format='%H%x09%s' | awk -F'\t' -v s="$subj" '$2==s {print $1; exit}')
        [ -n "$subj" ] && [ -n "$c" ] && ! reverted "$c" && printf '%s\t%s\t%s\n' "$s" "$c" "$(basename "$p")" >> "$st"
      elif git -C "$ROOT/$proj" apply --reverse --check "$p" 2>/dev/null; then
        cp "$p" "$STATE/$name/$s.patch"; printf '%s\t-\t%s\n' "$s" "$(basename "$p")" >> "$st"
      fi
    done
    [ -s "$st" ] && echo "[$name] stan odtworzony z drzewa: $(wc -l < "$st") nałożonych"
  fi

  # 1) cofnąć nałożone, których przepis już nie chce (usunięte albo zmienione) — od najnowszego
  mapfile -t rows < <(tac "$st")
  keep=()
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r s c f <<< "$row"
    if ! present "$c" "$s"; then
      echo "[$name] $f: zmiany już nie ma w drzewie (repo sync?) — nałożę od nowa"; continue
    fi
    if [ -n "${want[$s]:-}" ]; then keep=("$row" "${keep[@]}"); continue; fi
    echo "[$name] $f: usunięty albo zmieniony w przepisie — cofam"
    if [ "$c" = - ]; then
      git -C "$ROOT/$proj" apply -R "$STATE/$name/$s.patch" || { echo "[$name] nie da się odwrócić $f — rozwiązać ręcznie"; exit 1; }
    else
      G revert --no-edit "$c" >/dev/null || { G revert --abort || true; echo "[$name] cofnięcie $f koliduje z późniejszymi patchami — rozwiązać ręcznie"; exit 1; }
    fi
  done
  printf '%s\n' "${keep[@]}" | sed '/^$/d' > "$st.new"; mv "$st.new" "$st"

  # 2) nałożyć brakujące, w kolejności przepisu
  for p in "${patches[@]}"; do
    s=$(sum "$p"); f=$(basename "$p")
    if grep -q "^$s"$'\t' "$st"; then echo "[$name] $f: już nałożony"; continue; fi
    echo "[$name] $f"
    if is_fp "$p"; then
      G am -3 --keep-cr -q "$p" || {
        G am --abort || true
        echo "[$name] $f nie wchodzi na aktualny LineageOS — odśwież patch (scripts/check-patches.sh)"; exit 1; }
      printf '%s\t%s\t%s\n' "$s" "$(git -C "$ROOT/$proj" rev-parse HEAD)" "$f" >> "$st"
    else
      git -C "$ROOT/$proj" apply --check "$p"
      git -C "$ROOT/$proj" apply "$p"
      cp "$p" "$STATE/$name/$s.patch"; printf '%s\t-\t%s\n' "$s" "$f" >> "$st"
    fi
  done
  unset want
done
