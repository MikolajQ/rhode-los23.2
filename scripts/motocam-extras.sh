#!/usr/bin/env bash
# Moto Camera stockowa (MotCamera4 + MotCamera3AI + MotoSignature) do vendor/motocam-extras.
# Pliki wyciągnięte 21.09 debugfs-em z prawdziwych partycji product/system stocka
# XT2221-1_RHODE_RETEU_13_T2SRS33.72-22-4-11 (nie stockowy moduł Magiska — ta sama warstwa
# aplikacyjna, tylko przepakowana z system/product/* -> product/*, system/* -> system/*).
# Przetestowane 21.09 modułem KSU-Next (system-only, bo metamoduł magic_mount_rs montuje
# tylko /system): wszystkie obiektywy, portret, noc, wideo HEVC 1080p30. Ultra-Res 50 MP nie
# działa (brak w LineageOS mechanizmu ro.camera.cfa.packagelist z cameraservice Motoroli —
# świadomie bez łatki, decyzja 21.09) i to jedyna różnica względem testu.
#
# vendor/lib64/libcamxexternalformatutils.so ze stockowego modułu CELOWO POMINIĘTE: test 21.09
# (moduł systemowy KSU, mount tylko /system, WIĘC ten .so nigdy realnie nie trafił do /vendor)
# udowodnił, że wszystkie sprawdzone funkcje działają bez niego — nie ma potrzeby dotykać
# partycji vendor (bardziej wrażliwej na sepolicy/format) dla czegoś niepotwierdzonego jako wymagane.
#
# Zip (płaski układ partycji, NIE układ modułu Magiska/KSU z prefiksem system/):
#   product/priv-app/MotCamera4/MotCamera4.apk
#   product/app/MotCamera3AI/MotCamera3AI.apk
#   product/etc/permissions/com.motorola.camera3*.xml (4 pliki) + deviceowner-configuration-*.xml
#     + privapp-permissions-com.motorola.camera3.xml
#   product/etc/sysconfig/hiddenapi-whitelist-com.motorola.camera3.xml
#   system/app/{MotoSignatureApp,MotoSignature2App}/*.apk
#   system/etc/permissions/{com.motorola.motosignature,moto-core_services,moto-settings}.xml
#   system/framework/{com.motorola.motosignature,moto-core_services,moto-settings}.jar
set -euo pipefail
ROOT=${1:?korzeń drzewa}
ZIP=${2:?zip z Moto Camera}
DEST="$ROOT/vendor/motocam-extras"
rm -rf "$DEST" && mkdir -p "$DEST"
unzip -o -q "$ZIP" -d "$DEST"
[ -d "$DEST/product/priv-app/MotCamera4" ] || { echo "brak product/priv-app/MotCamera4 w zipie"; exit 1; }

bp="$DEST/Android.bp"; pmk="$DEST/extras.mk"; mods=()
printf '// Wygenerowane przez rhode-los23.2/scripts/motocam-extras.sh — nie edytować ręcznie.\nsoong_namespace {}\n' > "$bp"

# product/priv-app/<Nazwa>/<jeden apk> — privileged, product_specific (MotCamera4)
for dir in "$DEST"/product/priv-app/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  apk=$(find "$dir" -maxdepth 1 -name '*.apk' | head -1)
  [ -n "$apk" ] || { echo "BŁĄD: $name (product/priv-app) bez .apk"; exit 1; }
  rel=${apk#$DEST/}
  cat >> "$bp" <<BP

android_app_import {
    name: "$name",
    apk: "$rel",
    presigned: true,
    preprocessed: true,
    privileged: true,
    product_specific: true,
    dex_preopt: { enabled: false },
}
BP
  mods+=("$name")
done

# product/app/<Nazwa>/<jeden apk> — NIE privileged, product_specific (MotCamera3AI)
for dir in "$DEST"/product/app/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  apk=$(find "$dir" -maxdepth 1 -name '*.apk' | head -1)
  [ -n "$apk" ] || { echo "BŁĄD: $name (product/app) bez .apk"; exit 1; }
  rel=${apk#$DEST/}
  cat >> "$bp" <<BP

android_app_import {
    name: "$name",
    apk: "$rel",
    presigned: true,
    preprocessed: true,
    product_specific: true,
    dex_preopt: { enabled: false },
}
BP
  mods+=("$name")
done

# system/app/<Nazwa>/<jeden apk> — NIE privileged, NIE product_specific (MotoSignatureApp, MotoSignature2App)
for dir in "$DEST"/system/app/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  apk=$(find "$dir" -maxdepth 1 -name '*.apk' | head -1)
  [ -n "$apk" ] || { echo "BŁĄD: $name (system/app) bez .apk"; exit 1; }
  rel=${apk#$DEST/}
  cat >> "$bp" <<BP

android_app_import {
    name: "$name",
    apk: "$rel",
    presigned: true,
    preprocessed: true,
    dex_preopt: { enabled: false },
}
BP
  mods+=("$name")
done

# product/etc/{permissions,sysconfig}/*.xml
for sub in permissions sysconfig; do
  for xml in "$DEST"/product/etc/$sub/*.xml; do
    [ -e "$xml" ] || continue
    f=$(basename "$xml"); m="motocam_product_${sub}_${f%.xml}"; m=${m//[^A-Za-z0-9_]/_}
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

# system/etc/permissions/*.xml — NIE product_specific
for xml in "$DEST"/system/etc/permissions/*.xml; do
  [ -e "$xml" ] || continue
  f=$(basename "$xml"); m="motocam_system_permissions_${f%.xml}"; m=${m//[^A-Za-z0-9_]/_}
  cat >> "$bp" <<BP

prebuilt_etc {
    name: "$m",
    src: "system/etc/permissions/$f",
    filename: "$f",
    sub_dir: "permissions",
}
BP
  mods+=("$m")
done

# system/framework/*.jar — java_import (installable domyślnie ląduje w /system/framework)
for jar in "$DEST"/system/framework/*.jar; do
  [ -e "$jar" ] || continue
  f=$(basename "$jar"); m="${f%.jar}"; m=${m//[^A-Za-z0-9_.-]/_}
  rel=${jar#$DEST/}
  cat >> "$bp" <<BP

java_import {
    name: "$m",
    jars: ["$rel"],
    installable: true,
}
BP
  mods+=("$m")
done

{
  echo "# Wygenerowane przez rhode-los23.2/scripts/motocam-extras.sh"
  echo "PRODUCT_SOONG_NAMESPACES += vendor/motocam-extras"
  echo "PRODUCT_PACKAGES += \\"
  for m in "${mods[@]}"; do echo "    $m \\"; done
  echo
} > "$pmk"

printf '%s\n' "${mods[@]}" | grep -q '^MotCamera4' || { echo "BŁĄD: brak product/priv-app/MotCamera4"; exit 1; }
echo "motocam-extras: ${#mods[@]} modułów:"; printf '  %s\n' "${mods[@]}"
