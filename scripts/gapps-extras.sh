#!/usr/bin/env bash
# Rozpakowuje zip z dodatkami GApps do vendor/gapps-extras, skąd kopiuje je
# vendor/extra/product.mk (PRODUCT_COPY_FILES do partycji product).
#
# Oczekiwana struktura zipa (ta sama, co w module Magiska naprawiającym Family Link):
#   product/priv-app/GmsSupervision/base.apk
#   product/priv-app/GmsSupervision/split_config.xxhdpi.apk
#   product/priv-app/Gearhead/Gearhead.apk            (Android Auto, z NikGapps Addon-AndroidAuto)
#   product/etc/permissions/privapp-permissions-gearhead.xml
# Allowlist gms.supervision jest już w MindTheGapps (privapp-permissions-google-product.xml).
set -euo pipefail
ROOT=${1:?korzeń drzewa}
ZIP=${2:?zip z dodatkami}
DEST="$ROOT/vendor/gapps-extras"
rm -rf "$DEST" && mkdir -p "$DEST"
unzip -o -q "$ZIP" -d "$DEST"
[ -d "$DEST/product/priv-app/GmsSupervision" ] || { echo "brak product/priv-app/GmsSupervision w zipie"; exit 1; }
[ -d "$DEST/product/priv-app/Gearhead" ]       || { echo "brak product/priv-app/Gearhead w zipie"; exit 1; }
find "$DEST" -type f -name '*.apk' -exec chmod 0644 {} +
echo "gapps-extras:"; find "$DEST" -type f | sed "s|$DEST/|  |"
