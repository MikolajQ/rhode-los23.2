# rhode-los23.2 — przepis HAM

Build LineageOS 23.2 (Android 16 QPR2) dla Motorola Moto G52 (`rhode`) na bazie czystego manifestu
[LineageOS lineage-23.2](https://github.com/LineageOS/android/tree/lineage-23.2) (od 0.2.0; wcześniej
[Tomoms 16.2](https://github.com/tomoms/android/tree/16.2)), w chmurze Hetznera przez
[HAM](https://github.com/antony-jr/ham). Plan i decyzje: strona „Plan builda rhode".

Różnice względem oficjalnego LineageOS:

- **Wybrane zmiany Tomoms jako patche** (`patches/`, przegląd ~1500 jego commitów i uzasadnienia: `docs/przeglad-tomoms.md`):
  27 commitów drzew urządzenia (DT2W, readahead, `/vendor_dlkm`, 60 fps w Aperture, KTweak), PropImitationHooks
  (Play Integrity), hartowanie sieci i bionic z GrapheneOS (VPN lockdown bez wycieku DNS, sprawdzanie łączności bez Google,
  losowy MAC, strony ochronne stosu), wyłączanie Wi-Fi/Bluetooth po czasie, automatyczne nagrywanie rozmów
- **Pakiet wydajnościowy** (cel tego builda): jemalloc, `-O3`/LTO, nowsze Arm Optimized Routines, strojenie ART
  (`bg-dexopt=speed`), SurfaceFlinger, ~190 optymalizacji system_server/SystemUI, Launcher3 — `docs/przeglad-tomoms.md`
- **Jądro Tomoms** (optymalizacje baterii/płynności) z **KernelSU-Next** (manual hooks) w
  [forku](https://github.com/MikolajQ/android_kernel_motorola_sm6225/tree/16.2-ksun), przy każdym buildzie scalane z jądrem LineageOS
- **GApps w obrazie**: MindTheGapps (`baklava`) przycięte do zestawu NikGapps core + pełny Android Auto
  + `GmsSupervision` jako priv-app w `product` (Family Link — patrz nikgapps/config#15760)
- **Droid-ify** (zamiast F-Droida — ciężki, toporny) z repozytoriami IzzyOnDroid, NewPipe, IronFox; bez Privileged
  Extension (Droid-ify jej nie obsługuje) — instalacja aktualizacji przez root KSU-Next
- **WebView: prebuilt oficjalny LineageOS** (pakiet `com.android.webview`); do 22.09 był tu Cromite (de-Google + adblock) —
  zamieniony po [uazo/cromite#3085](https://github.com/uazo/cromite/issues/3085): patch Cromite wymuszający partycjonowanie
  połączeń wywalał SIGTRAP-em każdą apkę wołającą WebView preconnect z pustym kluczem (m.in. Google Mobile Ads SDK)
- **Bloker w obrazie**: `/system/etc/hosts` (adult + social + komunikatory poza WhatsApp/Signal) + domyślny Private DNS AdGuard Family; na telefonie AdAway (root)
- **Telefon dziecka**: manager KernelSU-Next instalowany po flashu z oryginalnego APK (nie da się go wbudować bez złamania podpisu — patrz vendor/extra `product.mk`), potem ukryty/za PIN-em; blokada nieznanych źródeł w Family Link
- **HAL wideo**: `libOmxVenc` deklaruje pełny zakres poziomów H.264/HEVC i przycina żądany do maksimum sterownika (bengal: 5.0/5) — bez tego GCam LMC 8.4 nie nagrywa (patrz `patches/hardware_qcom-caf_sm8250_media/`)
- **Moto Camera stockowa** (MotCamera4, MotCamera3AI, MotoSignature) obok Aperture — przetestowana 21.09 na telefonie
  modułem KSU-Next (wszystkie obiektywy, portret, noc, wideo HEVC; bez Ultra-Res 50 MP — brak w LineageOS mechanizmu
  `ro.camera.cfa.packagelist` z cameraservice Motoroli, świadomie bez łatki). Weryfikacja 9.0.85.32 jako ostatniej
  wersji dla rhode: bajt w bajt identyczna w firmware z 05.2025, więc nie ma nowszej do zdobycia. Opcjonalna (`motocam_zip`)
- **Play Integrity**: świeży, nie-beta fingerprint Pixela 10 Pro w `persist.sys.pihooks_*` (poprzedni, beta, przestał
  przechodzić nawet DEVICE integrity — patrz `android_vendor_extra` `product.mk`)
- bez Bellis i LogViewer; własne OTA z [rhode_releases](https://github.com/MikolajQ/rhode_releases)
- wersja `23.2-DATA-UNOFFICIAL-miq-rhode` (`TARGET_UNOFFICIAL_BUILD_ID` podmieniany w `ham.yml`; patch drzewa rhode od Tomoms ustawia `Tom`)

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

## Uruchomienie i sprzątanie serwera

**`ham get`/`ham clean` potrzebują prawdziwego pty** — pod gołym `nohup ... &` w tle wiszą bez śladu (brak
terminala blokuje nawet ekran potwierdzenia ceny, zanim dojdzie do sprawdzenia flagi `-n`). Odpalać pod
`script`: `script -qec "~/bin/rhode/ham get ..." log.txt`.

**Serwer** (od ham `6cfefa4`): domyślnie **CPX62** — 16 vCPU współdzielonych, 32 GB RAM, `/ham-build` na lokalnym
NVMe 640 GB, bez wolumenu (≈0,256 €/h brutto, 25.09.2026). Gdy Hetzner nie ma CPX62 w nbg1/fsn1/hel1, zapasowo
**CCX33** (8 vCPU dedykowanych) z wolumenem 400 GB (≈0,273 + 0,039 €/h). Inny typ: `ham get ... -m ccx33`.
Poprzednie buildy szły na CCX33 z wolumenem 400 GB i się w nim mieściły (źródła, `out/`, swap 48 GB).

**Po udanym buildzie serwer sprząta sam** — `ham-build` z forka [MikolajQ/ham](https://github.com/MikolajQ/ham)
(od `ee6b924`) po `post_build` — jeśli serwer ma wolumen — wyłącza swap na `/ham-build`, odmontowuje wolumen, odpina go i kasuje przez API
(token z `/root/.ham.json`), a na końcu kasuje własny serwer. Robi to także z `--keep-server` (flaga dotyczy tylko
porażki), więc nie zależy od tego komputera. Nieudany build zostaje żywy do debugowania (`-t`/`-b`), ale najwyżej **6 h**: timer systemd `ham-ttl` na serwerze
(od ham `cff6f1f`) woła potem `ham destroy-self` i kasuje wolumen i serwer — bez tego komputera. Dłużej:
`touch /tmp/ham-keep` albo `systemctl stop ham-ttl.timer` na serwerze. Pojedynczy krok przepisu ma limit 12 h.
zram: gdy jądro nie ma modułu (`linux-modules-extra`), build idzie bez zram, tylko na swapie 48 GB.

`ham get` wgrywa `ham-build` leżący obok `ham` (`~/bin/rhode/`) i przerywa, jeśli jego commit różni się od
klienta — oba budować razem: `make local` w `~/ham`. Osierocone wolumeny `build-*-vol` (bez serwera, >30 min)
kasuje każde `ham get` i `ham clean`.

Siatka bezpieczeństwa dla porażek: `~/bin/rhode/watchdog-cleanup.sh` jako systemd user timer
(`~/.config/systemd/user/rhode-watchdog.{service,timer}`, co 15 min, `loginctl enable-linger`) — kasuje serwery
starsze niż 8h, na których `ham build` już nie żyje, oraz osierocone wolumeny.

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
| `motocam_zip` | file | opcjonalny; zip z Moto Camera stockowej w płaskim układzie partycji (nie module Magiska): `product/priv-app/MotCamera4/`, `product/app/MotCamera3AI/`, `product/etc/{permissions,sysconfig}/*`, `system/app/{MotoSignatureApp,MotoSignature2App}/`, `system/etc/permissions/*.xml`, `system/framework/*.jar`; skrypt generuje `Android.bp` (`android_app_import`/`prebuilt_etc`/`java_import`) i `extras.mk`; gotowy zip: `~/Pulpit/Rhode/motocam/motocam-gapps-extras.zip`; puste = bez Moto Camera |
| `keys_zip` | file | własne klucze (`*.pk8`, `*.x509.pem`, `<apex>.pem`); z nimi build idzie przez `mka target-files-package otatools` + `scripts/sign.sh` (wiki LineageOS „Signing builds"); puste = test-keys i `mka bacon` |

## Układ

```
ham.yml                      przepis
rhode.xml                    .repo/local_manifests
patches/vendor_gapps/        cięcia listy pakietów MTG (git apply)
patches/<projekt>/           serie git format-patch (git am -3) — zmiany Tomoms przeniesione na LineageOS, patrz docs/przeglad-tomoms.md
patches/hardware_qcom-caf_sm8250_media/  enkoder wideo: pełny zakres poziomów + clamp (wideo w GCam/LMC 8.4)
scripts/fetch-hosts.sh       /system/etc/hosts: StevenBlack porn+social (przypięty commit) + lists/, minus WhatsApp/Signal
scripts/fetch-droidify.sh    Droid-ify z release'u, przypięty tag + SHA-256
lists/                       communicators-block.txt (Telegram, Discord, Viber…), allow.txt (WhatsApp, Signal)
scripts/apply-patches.sh     patches/*: seria format-patch -> git am -3, zwykły diff -> git apply; pierwszy błąd = stop
scripts/check-patches.sh     lokalnie przed ham get: czy patche wchodzą na aktualny LineageOS i czy jądro scala się bez konfliktu
scripts/gapps-extras.sh      zip -> vendor/gapps-extras + Android.bp / splits/Android.mk / extras.mk (splity jako prebuilty ETC; .apk nie może iść przez PRODUCT_COPY_FILES)
scripts/motocam-extras.sh    zip -> vendor/motocam-extras + Android.bp / extras.mk (Moto Camera stockowa, opcjonalne)
scripts/check-privapp.py     allowlist vs. uprawnienia privileged z APK; brak = stop przed mka
scripts/sign.sh              sign_target_files_apks + ota_from_target_files z /root/.android-certs (listy APEX z wiki); boot/dtbo/vendor_boot -> $OUT/signed-images
scripts/upload.sh            post_build: release + rhode.json
scripts/staleness.sh         lokalnie przed ham get: check-patches.sh, KernelSU-Next (legacy) vs pin,
                              Droid-ify vs latest release, ham fork vs upstream — tylko raportuje, nic nie merguje
scripts/inspect-zip.sh       lokalnie po pobraniu zipa: kontrola obrazu przed flashem (debugfs, bez roota)
```
