# rhode-los23.2 — przepis HAM

Build LineageOS 23.2 (Android 16 QPR2) dla Motorola Moto G52 (`rhode`) na bazie manifestu
[Tomoms 16.2](https://github.com/tomoms/android/tree/16.2), w chmurze Hetznera przez
[HAM](https://github.com/antony-jr/ham). Plan i decyzje: strona „Plan builda rhode".

Różnice względem buildów Tomoms:

- **KernelSU-Next** (manual hooks) w [forku kernela](https://github.com/MikolajQ/android_kernel_motorola_sm6225/tree/16.2-ksun)
- **GApps w obrazie**: MindTheGapps (`baklava`) przycięte do zestawu NikGapps core + pełny Android Auto
  + `GmsSupervision` jako priv-app w `product` (Family Link — patrz nikgapps/config#15760)
- **F-Droid** z repozytoriami IzzyOnDroid, NewPipe, IronFox (same adresy, bez APK w obrazie)
- **WebView: Cromite** (`org.cromite.webview`, de-Google + adblock) zamiast prebuiltu LineageOS; APK pobierany przy buildzie
- **Bloker w obrazie**: `/system/etc/hosts` (adult + social + komunikatory poza WhatsApp/Signal) + domyślny Private DNS AdGuard Family; na telefonie AdAway (root)
- **Telefon dziecka**: oryginalny manager KernelSU-Next w obrazie, ukryty/za PIN-em; blokada nieznanych źródeł w Family Link
- bez Bellis i LogViewer; własne OTA z [rhode_releases](https://github.com/MikolajQ/rhode_releases)

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
| `gapps_extras_zip` | file | zip: `product/priv-app/GmsSupervision/base.apk` + `split_config.xxhdpi.apk` (z modułu Magiska) + `product/etc/permissions/com.google.android.projection.gearhead.xml` (pełna allowlist AA z NikGapps); Android Auto = stub z MTG + Play; skrypt generuje `Android.bp` (jeden APK → `android_app_import`), `splits/Android.mk` (splity → prebuilty ETC do `priv-app/`) i `extras.mk` |
| `keys_zip` | file | opcjonalnie: `vendor/lineage-priv/keys` |

## Układ

```
ham.yml                      przepis
rhode.xml                    .repo/local_manifests
patches/vendor_gapps/        cięcia listy pakietów MTG (git apply)
patches/vendor_lineage/      bez prywatnych Trichrome* z vendor/lineage Tomoms
scripts/fetch-webview.sh     Cromite SystemWebView z release'u, przypięty tag + SHA-256
scripts/fetch-hosts.sh       /system/etc/hosts: StevenBlack porn+social (przypięty commit) + lists/, minus WhatsApp/Signal
lists/                       communicators-block.txt (Telegram, Discord, Viber…), allow.txt (WhatsApp, Signal)
scripts/apply-patches.sh
scripts/gapps-extras.sh      zip -> vendor/gapps-extras + Android.bp / splits/Android.mk / extras.mk (splity jako prebuilty ETC; .apk nie może iść przez PRODUCT_COPY_FILES)
scripts/check-privapp.py     allowlist vs. uprawnienia privileged z APK; brak = stop przed mka
scripts/upload.sh            post_build: release + rhode.json
scripts/staleness.sh         lokalnie przed ham get: o ile forki Tomoms odstają od LineageOS
scripts/inspect-zip.sh       lokalnie po pobraniu zipa: kontrola obrazu przed flashem (debugfs, bez roota)
```
