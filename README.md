# rhode-los23.2 — przepis HAM

Build LineageOS 23.2 (Android 16 QPR2) dla Motorola Moto G52 (`rhode`) na bazie manifestu
[Tomoms 16.2](https://github.com/tomoms/android/tree/16.2), w chmurze Hetznera przez
[HAM](https://github.com/antony-jr/ham). Plan i decyzje: strona „Plan builda rhode".

Różnice względem buildów Tomoms:

- **KernelSU-Next** (manual hooks) w [forku kernela](https://github.com/MikolajQ/android_kernel_motorola_sm6225/tree/16.2-ksun)
- **GApps w obrazie**: MindTheGapps (`baklava`) przycięte do zestawu NikGapps core + pełny Android Auto
  + `GmsSupervision` jako priv-app w `product` (Family Link — patrz nikgapps/config#15760)
- **F-Droid** z repozytoriami IzzyOnDroid, NewPipe, IronFox (same adresy, bez APK w obrazie)
- **WebView: Cromite** (pakiet `com.android.webview`, de-Google + adblock) zamiast prebuiltu LineageOS; APK pobierany przy buildzie
- **Bloker w obrazie**: `/system/etc/hosts` (adult + social + komunikatory poza WhatsApp/Signal) + domyślny Private DNS AdGuard Family; na telefonie AdAway (root)
- **Telefon dziecka**: manager KernelSU-Next instalowany po flashu z oryginalnego APK (nie da się go wbudować bez złamania podpisu — patrz vendor/extra `product.mk`), potem ukryty/za PIN-em; blokada nieznanych źródeł w Family Link
- **HAL wideo**: `libOmxVenc` deklaruje pełny zakres poziomów H.264/HEVC i przycina żądany do maksimum sterownika (bengal: 5.0/5) — bez tego GCam LMC 8.4 nie nagrywa (patrz `patches/hardware_qcom-caf_sm8250_media/`)
- bez Bellis i LogViewer; własne OTA z [rhode_releases](https://github.com/MikolajQ/rhode_releases)
- wersja `23.2-DATA-UNOFFICIAL-miq-rhode` (`TARGET_UNOFFICIAL_BUILD_ID` podmieniany w `ham.yml`; w drzewie Tomoms jest `Tom`)

## Instalacja na telefonie (Virtual A/B — kolejność ma znaczenie)

1. `fastboot boot boot.img` (obraz z release'u = ten z `payload.bin`, z naszymi otacerts) → recovery.
2. **Factory Reset → Format data / factory reset** — *przed* sideloadem. Format po sideloadzie kasuje `/metadata/ota`
   (stan snapshotów Virtual A/B) i nadmiar COW w `/data`: nowy slot zostaje z surowymi, starymi partycjami i wpada w recovery.
3. Apply Update → Apply from ADB → `adb -d sideload lineage-…-signed.zip`. Dodatki: No. Potem **Reboot system now**, nic więcej.
4. Pierwszy rozruch: logo → animacja (snapshoty scalają się w tle po udanym starcie). Manager KernelSU-Next: zainstalować ręcznie.

Pułapki z 2026-09-19: bootloader Motoroli blokuje `erase`/`flash` na `misc`, `persist`, `frp` (bit 5 atrybutów GPT);
`slot-successful`/`retry-count` to bity 48–55 atrybutów GPT partycji `boot_*` na LUN-ach 3 (a) i 5 (b) — **nie edytować
sgdisk-iem** (bootloader zgubił slot; ratunek: `fastboot flash partition gpt.bin` ze stockowego firmware'u, MD5 z `flashfile.xml`).
`ro.debuggable=0` (build user): `adb root` nie działa; logi startu: `adb logcat -b all -d` w oknie animacji, zanim padnie.

## Uruchomienie

```
ham init                       # token Hetznera, klucz ham-ssh-key
ham get MikolajQ@gh/rhode-los23.2 -k -t -b
```

Flagi `-k -t -b` zostawiają serwer po błędzie / zerwanym śledzeniu / nieudanym buildzie.
Po debugowaniu: `ham clean`. Limit HAM: serwer starszy niż 24 h jest kasowany.

## Argumenty (ham get pyta o nie)

| id | typ | co |
|---|---|---|
| `gh_token` | secret | token GitHub z `repo` — `upload.sh` tworzy release i aktualizuje `23.x/rhode.json` |
| `gapps_extras_zip` | file | zip: `product/priv-app/GmsSupervision/GmsSupervision.apk` (stub Google 0.1.453788429 z APKMirror „System parental controls" — Play nadpisze pełną wersją z flagą PRIVILEGED) + `product/etc/permissions/com.google.android.projection.gearhead.xml` (pełna allowlist AA z NikGapps); skrypt generuje `Android.bp` (jeden APK → `android_app_import`), `splits/Android.mk` (gdyby były splity → prebuilty ETC) i `extras.mk` |
| `keys_zip` | file | własne klucze (`*.pk8`, `*.x509.pem`, `<apex>.pem`); z nimi build idzie przez `mka target-files-package otatools` + `scripts/sign.sh` (wiki LineageOS „Signing builds"); puste = test-keys i `mka bacon` |

## Układ

```
ham.yml                      przepis
rhode.xml                    .repo/local_manifests
patches/vendor_gapps/        cięcia listy pakietów MTG (git apply)
patches/vendor_lineage/      bez prywatnych Trichrome* z vendor/lineage Tomoms
patches/hardware_qcom-caf_sm8250_media/  enkoder wideo: pełny zakres poziomów + clamp (wideo w GCam/LMC 8.4)
scripts/fetch-webview.sh     Cromite SystemWebView z release'u, przypięty tag + SHA-256
scripts/fetch-hosts.sh       /system/etc/hosts: StevenBlack porn+social (przypięty commit) + lists/, minus WhatsApp/Signal
lists/                       communicators-block.txt (Telegram, Discord, Viber…), allow.txt (WhatsApp, Signal)
scripts/apply-patches.sh
scripts/gapps-extras.sh      zip -> vendor/gapps-extras + Android.bp / splits/Android.mk / extras.mk (splity jako prebuilty ETC; .apk nie może iść przez PRODUCT_COPY_FILES)
scripts/check-privapp.py     allowlist vs. uprawnienia privileged z APK; brak = stop przed mka
scripts/sign.sh              sign_target_files_apks + ota_from_target_files z /root/.android-certs (listy APEX z wiki); boot/dtbo/vendor_boot -> $OUT/signed-images
scripts/upload.sh            post_build: release + rhode.json
scripts/staleness.sh         lokalnie przed ham get: o ile forki Tomoms odstają od LineageOS
scripts/inspect-zip.sh       lokalnie po pobraniu zipa: kontrola obrazu przed flashem (debugfs, bez roota)
```
