#!/usr/bin/env bash
# Podpisywanie builda własnymi kluczami — procedura z wiki LineageOS "Signing builds" (23.x):
#   mka target-files-package otatools  ->  sign_target_files_apks  ->  ota_from_target_files
# Klucze: /root/.android-certs (rozpakowane z keys_zip przez ham.yml): <nazwa>.pk8 + .x509.pem dla APK,
# <apex>.pk8 + .x509.pem (RSA 4096) + <apex>.pem (PKCS8) dla APEX-ów. Listy apexapks/apexes = wiki, stan 2026-09-17.
set -euo pipefail
ROOT=${1:?korzeń drzewa}
CERTS=${2:-/root/.android-certs}
cd "$ROOT"
[ -s "$CERTS/releasekey.pk8" ] || { echo "brak $CERTS/releasekey.pk8"; exit 1; }
source build/envsetup.sh >/dev/null
breakfast rhode >/dev/null
OUT=${OUT:-out/target/product/rhode}
TF=$(ls -t "$OUT"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip | head -1)
[ -s "$TF" ] || { echo "brak target_files zip — najpierw mka target-files-package otatools"; exit 1; }

APEXAPKS="com.android.appsearch.apk AdServicesApk FederatedCompute HalfSheetUX HealthConnectBackupRestore HealthConnectController OsuLogin SafetyCenterResources ServiceConnectivityResources ServiceUwbResources ServiceWifiResources TelecomServiceResources TelecomUi WebAppService WifiDialog"
APEXES="com.android.adbd com.android.adservices com.android.adservices.api com.android.appsearch com.android.art com.android.bluetooth com.android.bt com.android.btservices com.android.cellbroadcast com.android.compos com.android.configinfrastructure com.android.connectivity.resources com.android.conscrypt com.android.crashrecovery com.android.devicelock com.android.extservices com.android.graphics.pdf com.android.hardware.authsecret com.android.hardware.biometrics.face.virtual com.android.hardware.biometrics.fingerprint.virtual com.android.hardware.boot com.android.hardware.cas com.android.hardware.contexthub com.android.hardware.drm.clearkey com.android.hardware.dumpstate com.android.hardware.gatekeeper.nonsecure com.android.hardware.neuralnetworks com.android.hardware.power com.android.hardware.rebootescrow com.android.hardware.thermal com.android.hardware.threadnetwork com.android.hardware.uwb com.android.hardware.vibrator com.android.hardware.wifi com.android.healthfitness com.android.hotspot2.osulogin com.android.i18n com.android.ipsec com.android.media com.android.media.swcodec com.android.mediaprovider com.android.nearby.halfsheet com.android.networkstack.tethering com.android.neuralnetworks com.android.nfcservices com.android.npumanager com.android.ondevicepersonalization com.android.os.statsd com.android.permission com.android.profiling com.android.resolv com.android.rkpd com.android.runtime com.android.safetycenter.resources com.android.scheduling com.android.sdkext com.android.support.apexer com.android.telephony com.android.telephonycore com.android.telephonymodules com.android.tethering com.android.tzdata com.android.uprobestats com.android.uwb com.android.uwb.resources com.android.virt com.android.vndk.current com.android.vndk.current.on_vendor com.android.webapp com.android.wifi com.android.wifi.dialog com.android.wifi.resources com.google.pixel.camera.hal com.google.pixel.vibrator.hal com.qorvo.uwb"

args=()
for a in $APEXAPKS; do args+=(--extra_apks "$a.apk=$CERTS/releasekey"); done
for a in $APEXES; do
  [ -s "$CERTS/$a.pk8" ] && [ -s "$CERTS/$a.pem" ] || { echo "brak klucza APEX $a w $CERTS"; exit 1; }
  args+=(--extra_apks "$a.apex=$CERTS/$a" --extra_apex_payload_key "$a.apex=$CERTS/$a.pem")
done

echo "== sign_target_files_apks ($(basename "$TF"))"
sign_target_files_apks -o -d "$CERTS" "${args[@]}" "$TF" "$OUT/signed-target_files.zip"

VER=$(grep -m1 '^ro.lineage.version=' "$OUT/system/build.prop" | cut -d= -f2)   # np. 23.2-20260917-UNOFFICIAL-rhode
ZIP="$OUT/lineage-${VER}-signed.zip"
echo "== ota_from_target_files -> $(basename "$ZIP")"
ota_from_target_files -k "$CERTS/releasekey" --block --backup=true "$OUT/signed-target_files.zip" "$ZIP"
ls -la "$ZIP" | awk '{print $5" B", $9}'
for img in boot dtbo vendor_boot; do [ -s "$OUT/$img.img" ] && echo "  $img.img: $(stat -c %s "$OUT/$img.img") B"; done
