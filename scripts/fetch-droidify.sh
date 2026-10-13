#!/usr/bin/env bash
# Droid-ify (klient F-Droid) jako aplikacja systemowa, zamiast oficjalnego F-Droida (decyzja 21.09:
# F-Droid ciężki i toporny). Droid-ify NIE ma Privileged Extension ani uprawnienia INSTALL_PACKAGES
# (sprawdzony manifest apk) - cicha instalacja aktualizacji tylko przez root (KSU-Next), user musi
# przyznać apce dostęp do su przy pierwszym użyciu. Repozytoria (IzzyOnDroid/NewPipe/IronFox) NIE
# wymagają osobnej konfiguracji: Droid-ify OemRepositoryParser czyta ten sam plik i format co stary
# klient F-Droid (7-elementowe chunki XML), z tych samych ścieżek, m.in. /system/etc/org.fdroid.fdroid/
# - to jest fdroid/additional_repos.xml, kopiowany osobnym krokiem w ham.yml, bez zmian.
# Aktualizacja: podmienić TAG i SHA256 (digest jest w API GitHuba: releases/latest -> assets[].digest).
set -euo pipefail
ROOT=${1:?korzeń drzewa}
TAG="v0.7.8"
SHA256="3e7934ff9b811c2f77794793381241095a02bac2d163bf922cb5a5a0ed25ca82"
URL="https://github.com/Droid-ify/client/releases/download/$TAG/app-release.apk"
DEST="$ROOT/external/droidify"
mkdir -p "$DEST"
# Do pliku tymczasowego i z ponowieniami: urwane pobranie zostawiało plik, którego suma już nigdy się nie
# zgadzała ([ -s ] go nie odróżniał), więc każde wznowienie builda padało w tym kroku.
apk="$DEST/droidify.apk"
if ! { [ -s "$apk" ] && echo "$SHA256  $apk" | sha256sum -c --quiet - 2>/dev/null; }; then
  for try in 1 2 3; do
    rm -f "$apk" "$apk.part"
    if curl -fL --retry 5 --retry-all-errors --retry-delay 10 -o "$apk.part" "$URL" \
       && echo "$SHA256  $apk.part" | sha256sum -c --quiet -; then
      mv "$apk.part" "$apk"; break
    fi
    [ "$try" = 3 ] && { echo "Droid-ify: pobranie nieudane albo zła suma (3 próby)"; exit 1; }
    sleep $((try * 20))
  done
fi
echo "$SHA256  $apk" | sha256sum -c -
cat > "$DEST/Android.bp" <<'BP'
// Droid-ify (pakiet com.looker.droidify), pobierany przez scripts/fetch-droidify.sh.
// .so w apk juz sa nieskompresowane (Stored) - preprocessed:true dziala bez modyfikacji pliku,
// jak w prebuilt-cie F-Droida Tomomsa.
android_app_import {
    name: "Droidify",
    product_specific: true,
    presigned: true,
    preprocessed: true,
    dex_preopt: {
        enabled: false,
    },
    arch: {
        arm64: {
            apk: "droidify.apk",
        },
    },
}
BP
echo "droidify: $DEST/droidify.apk ($(du -m "$DEST/droidify.apk" | cut -f1) MB), $TAG"
