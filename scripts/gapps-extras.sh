#!/usr/bin/env bash
# Rozpakowuje zip z dodatkami GApps do vendor/gapps-extras i GENERUJE moduły builda:
#   Android.bp  — android_app_import (privileged, product) dla każdego product/priv-app/<Nazwa>/<jeden>.apk
#                 oraz prebuilt_etc dla product/etc/permissions/*.xml i product/etc/sysconfig/*.xml
#   extras.mk   — PRODUCT_PACKAGES z tymi modułami; vendor/extra/product.mk robi inherit-product-if-exists
# Dlaczego nie PRODUCT_COPY_FILES: build/make odrzuca .apk w PRODUCT_COPY_FILES ("use BUILD_PREBUILT instead").
#
# Wymagania wobec zipa:
#   product/priv-app/GmsSupervision/<jeden plik>.apk   — JEDEN APK (nodpi/universal); android_app_import nie zna splitów
#   product/etc/permissions/com.google.android.projection.gearhead.xml — pełna allowlist Android Auto z NikGapps
#       (71 uprawnień vs 19 w MTG); sam stub AndroidAutoStub i overlay roli automotive projection daje MindTheGapps,
#       pełny Android Auto doinstalowuje Play i dziedziczy uprawnienia. Allowlisty z wielu plików są sumowane.
# Allowlist gms.supervision jest już w MindTheGapps (privapp-permissions-google-product.xml).
set -euo pipefail
ROOT=${1:?korzeń drzewa}
ZIP=${2:?zip z dodatkami}
DEST="$ROOT/vendor/gapps-extras"
rm -rf "$DEST" && mkdir -p "$DEST"
unzip -o -q "$ZIP" -d "$DEST"
[ -d "$DEST/product/priv-app" ] || { echo "brak product/priv-app w zipie"; exit 1; }

bp="$DEST/Android.bp"; mk="$DEST/extras.mk"; mods=()
printf '// Wygenerowane przez rhode-los23.2/scripts/gapps-extras.sh — nie edytować ręcznie.\nsoong_namespace {}\n' > "$bp"
for dir in "$DEST"/product/priv-app/*/; do
  name=$(basename "$dir")
  mapfile -t apks < <(find "$dir" -maxdepth 1 -name '*.apk' | sort)
  if [ ${#apks[@]} -ne 1 ]; then
    echo "BŁĄD: $name ma ${#apks[@]} plików .apk — potrzebny dokładnie jeden (splity: wziąć wariant nodpi/universal tej samej wersji)"; exit 1
  fi
  apk=${apks[0]}; rel=${apk#$DEST/}
  cat >> "$bp" <<BP

android_app_import {
    name: "$name",
    apk: "$rel",
    presigned: true,
    preprocessed: true,
    privileged: true,
    product_specific: true,
    dex_preopt: {
        enabled: false,
    },
}
BP
  mods+=("$name")
done
for sub in permissions sysconfig default-permissions; do
  for xml in "$DEST"/product/etc/$sub/*.xml; do
    [ -e "$xml" ] || continue
    f=$(basename "$xml"); m="gapps_extras_${sub}_${f%.xml}"; m=${m//[^A-Za-z0-9_]/_}
    cat >> "$bp" <<BP

prebuilt_etc {
    name: "$m",
    src: "product/etc/$sub/$f",
    filename: "$f",
    sub_dir: "$sub",
    product_specific: true,
}
BP
    mods+=("$m")
  done
done
{
  echo "# Wygenerowane przez rhode-los23.2/scripts/gapps-extras.sh"
  echo "PRODUCT_SOONG_NAMESPACES += vendor/gapps-extras"
  echo "PRODUCT_PACKAGES += \\"
  for m in "${mods[@]}"; do echo "    $m \\"; done
  echo
} > "$mk"
for req in GmsSupervision; do printf '%s\n' "${mods[@]}" | grep -qx "$req" || { echo "BŁĄD: brak product/priv-app/$req"; exit 1; }; done
echo "gapps-extras: ${#mods[@]} modułów:"; printf '  %s\n' "${mods[@]}"
