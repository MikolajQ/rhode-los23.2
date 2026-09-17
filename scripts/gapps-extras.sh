#!/usr/bin/env bash
# Rozpakowuje zip z dodatkami GApps do vendor/gapps-extras i GENERUJE moduły builda:
#   Android.bp         — android_app_import (privileged, product) dla katalogu product/priv-app/<Nazwa>/ z JEDNYM .apk
#                        oraz prebuilt_etc dla product/etc/{permissions,sysconfig,default-permissions}/*.xml
#   splits/Android.mk  — dla katalogu z WIELOMA .apk (base.apk + split_config.*.apk): prebuilty klasy ETC
#                        z LOCAL_MODULE_PATH do priv-app/<Nazwa>/ — surowe pliki, podpis Google nietknięty,
#                        PackageManager czyta katalog klastrowy tak samo jak po module Magiska
#   extras.mk          — PRODUCT_PACKAGES; vendor/extra/product.mk robi inherit-product-if-exists
# Dlaczego nie PRODUCT_COPY_FILES: build/make odrzuca .apk ("use BUILD_PREBUILT instead") — i to właśnie robimy.
#
# Zip:
#   product/priv-app/GmsSupervision/GmsSupervision.apk — STUB Google 0.1.453788429 (APKMirror "System parental controls",
#       41 KB, nodpi): placeholder w priv-app, Play nadpisuje go pełną wersją, która dziedziczy flagę PRIVILEGED
#       (ten sam mechanizm, co AndroidAutoStub). Alternatywnie base.apk + split_config.* z modułu — wtedy prebuilty ETC.
#   product/etc/permissions/com.google.android.projection.gearhead.xml  (pełna allowlist AA z NikGapps)
# Allowlist gms.supervision jest w MindTheGapps (privapp-permissions-google-product.xml).
set -euo pipefail
ROOT=${1:?korzeń drzewa}
ZIP=${2:?zip z dodatkami}
DEST="$ROOT/vendor/gapps-extras"
rm -rf "$DEST" && mkdir -p "$DEST/splits"
unzip -o -q "$ZIP" -d "$DEST"
[ -d "$DEST/product/priv-app" ] || { echo "brak product/priv-app w zipie"; exit 1; }

bp="$DEST/Android.bp"; mk="$DEST/splits/Android.mk"; pmk="$DEST/extras.mk"; mods=()
printf '// Wygenerowane przez rhode-los23.2/scripts/gapps-extras.sh — nie edytować ręcznie.\nsoong_namespace {}\n' > "$bp"
printf '# Wygenerowane przez rhode-los23.2/scripts/gapps-extras.sh — prebuilty ETC dla katalogów ze splitami.\nLOCAL_PATH := $(call my-dir)/..\n' > "$mk"

for dir in "$DEST"/product/priv-app/*/; do
  name=$(basename "$dir")
  mapfile -t apks < <(find "$dir" -maxdepth 1 -name '*.apk' | sort)
  [ ${#apks[@]} -ge 1 ] || { echo "BŁĄD: $name bez .apk"; exit 1; }
  if [ ${#apks[@]} -eq 1 ]; then
    rel=${apks[0]#$DEST/}
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
  else
    [ -e "$dir/base.apk" ] || { echo "BŁĄD: $name ma ${#apks[@]} .apk, ale bez base.apk"; exit 1; }
    for apk in "${apks[@]}"; do
      f=$(basename "$apk"); m="${name}-${f%.apk}"; m=${m//[^A-Za-z0-9_.-]/_}
      cat >> "$mk" <<MK

include \$(CLEAR_VARS)
LOCAL_MODULE := $m
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_OWNER := gapps
LOCAL_SRC_FILES := product/priv-app/$name/$f
LOCAL_MODULE_STEM := $f
LOCAL_PRODUCT_MODULE := true
LOCAL_MODULE_PATH := \$(TARGET_OUT_PRODUCT)/priv-app/$name
include \$(BUILD_PREBUILT)
MK
      mods+=("$m")
    done
    echo "gapps-extras: $name jako ${#apks[@]} splitów (prebuilty ETC): $(printf '%s ' "${apks[@]##*/}")"
  fi
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
} > "$pmk"
printf '%s\n' "${mods[@]}" | grep -q '^GmsSupervision' || { echo "BŁĄD: brak product/priv-app/GmsSupervision"; exit 1; }
echo "gapps-extras: ${#mods[@]} modułów:"; printf '  %s\n' "${mods[@]}"
