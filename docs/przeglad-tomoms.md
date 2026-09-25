# Przegląd zmian Tomoms 16.2 względem LineageOS 23.2 (25.09.2026)

Cel (wariant A+): baza = czysty LineageOS `lineage-23.2` (zawsze najświeższy, łatki ASB tego samego dnia),
plus wybrane zmiany Tomoms, których sens sprawdziliśmy, plus nasze łatki. Kod źródłowy analizy:
`~/build/tomoms-audit` (`audit.sh`, listy w `out/*.own`).

## Skala

| Obszar | Commity własne Tomoms | Zaległość względem LOS |
|---|---|---|
| 48 forków userspace (frameworks, bionic, art, aplikacje…) | ~1510, w tym `frameworks/base` 670, `Settings` 169, `arm-optimized-routines` 177 (nowszy upstream ARM z yaap) | `frameworks/base` 26, `frameworks/av` 6, `Nfc` 6, `vendor/lineage` 6… (m.in. ASB z 19.09) |
| Drzewa urządzenia rhode / sm6225-common | 9 / 18 | 0 / 0 |
| Jądro sm6225 | 942 (230 × Sultan Alsawaf: simple_lmk, optymalizacje arm64/mm/PM) | 8 (merge LOS z 10.09) |

Większość commitów w `frameworks/base` i `Settings` to „custom ROM layer” zebrany z crDroid/Axion/Evolution
(rmp22, Pranav Vashi, minaripenguin, Ghosuto, Dmitrii) oraz z GrapheneOS (Dmitry Muhomor, Daniel Micay).
Tego nie da się przenosić hurtem — każda miesięczna aktualizacja LOS rodziłaby konflikty w setkach miejsc.
Przenosimy **mały, samodzielny zestaw** jako patche w przepisie (`patches/<projekt>/`), resztę świadomie pomijamy.

## Werdykty

### PRZENIEŚĆ — jądro i drzewa urządzenia (bez zmian względem dziś)
- **Jądro Tomoms + nasze 5 commitów KSU-Next**, a przy buildzie automatyczny merge `LineageOS lineage-23.2`
  do jądra (Tomoms i tak merguje LOS co kilka dni, więc konflikty są rzadkie; konflikt = build staje od razu).
  Uzasadnienie: 942 commity to w większości dopracowane pod kątem baterii i płynności (deepsleep zamiast s2idle,
  simple_lmk, szybsze memcpy/crc32/lz4, threaded NAPI, BBR), jądro telefonu działa na nim od miesięcy,
  a nasze hooki KSU-Next są pisane właśnie pod to drzewo. Przejście na jądro LOS oznaczałoby przeniesienie KSU
  i ryzyko, bez zysku w bezpieczeństwie (jądro jest i tak tylko ~1 tydzień za LOS).
- **Wszystkie 27 commitów drzew urządzenia** (jako patche na drzewa LOS): MGLRU, readahead 128 KB, DT2W,
  `/vendor_dlkm`, 60 fps w Aperture, strojenie Wi-Fi INI, KTweak (scheduler), `disable_backpressure`,
  SUPL GrapheneOS. Część jest sprzężona z jego jądrem (`PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false`
  — jego defconfig wyłącza opcje, których wymaga VINTF; MGLRU; `/vendor_dlkm`), więc jądro i drzewa idą w parze.
  „Custom build ID” zastępujemy wprost naszym `miq`.

### PRZENIEŚĆ — Play Integrity (warunek działania Play/banków)
Nasz `vendor/extra/product.mk` ustawia `persist.sys.pihooks_*` i `PihooksGmsFp` — **to działa tylko dzięki
PropImitationHooks Tomoms**; w LineageOS tego nie ma (0 plików PIHooks w `lineage-23.2`). Bez tego telefon
straci certyfikację Play. Zestaw (~20 commitów): `frameworks/base` PIHooks (bez KeyboxImitation — keyboxa i tak
nie mamy), `bionic` natywne PIHooks, `build/soong` sysprops pihook, `system/core` spoofing propów init
(`verifiedbootstate`, `ro.boot.*`). Alternatywa bez patchy: moduł KSU-Next PlayIntegrityFork — do decyzji.

### PRZENIEŚĆ — prywatność i bezpieczeństwo (małe, rzadko konfliktują)
- `system/netd`: poprawka wycieku DNS w trybie VPN lockdown, zapora multicast (GrapheneOS).
- `packages/modules/Connectivity` + `NetworkStack` + `CaptivePortalLogin`: sprawdzanie łączności przez serwery
  GrapheneOS/Kuketz zamiast Google, DNS Cloudflare zamiast Google w diagnostyce; blokada `SO_BINDTODEVICE`
  i multicast dla aplikacji pod VPN lockdown.
- `packages/modules/Wifi` + `NetworkStack`: losowy MAC przy każdym połączeniu (opcja), brak wysyłania nazwy
  hosta w DHCP domyślnie.
- `frameworks/base` (pojedyncze, konfiguracyjne): NTP `pool.ntp.org`, SUPL GrapheneOS, `Build.SERIAL=UNKNOWN`,
  poprawka `RecoverySystem.verifyPackage` (GrapheneOS), ukrywanie wrażliwych treści na ekranie blokady domyślnie.
- `bionic` — hartowanie GrapheneOS (strony ochronne stosu wątków, read-only `__stack_chk_guard`, `explicit_bzero`,
  blokujący `getrandom`); alokator: jemalloc (pakiet wydajnościowy, niżej).

### DO DECYZJI — funkcje użytkowe (przenosimy tylko te, z których korzystasz)
Każda to 1–6 commitów w 1–3 repozytoriach: limit ładowania od 50% (lineage-sdk + LineageParts; w LOS
najniżej 70%), automatyczne nagrywanie rozmów (Dialer), wyłączanie Wi-Fi/BT po czasie bezczynności, zrzut ekranu
trzema palcami, tryb snu (Sleep Mode), dodatkowi dostawcy Private DNS w Ustawieniach, „muzyczny chip”
na pasku stanu, animacje ładowania, sejf w Glimpse, menedżer klientów hotspotu.

### POMINĄĆ — z uzasadnieniem
- ~~jemalloc zamiast scudo~~, ~~flagi kompilacji~~, ~~mikrooptymalizacje~~ — **przeniesione 25.09** po decyzji: celem
  builda jest wydajność na starym telefonie z minimalnym dostępem do sieci (patrz „Pakiet wydajnościowy”).
- **Osłabienia bezpieczeństwa**: `Allow signature spoofing on user builds`, `APK signature scheme v1 for API 30+`,
  `fs_mgr: Allow remount on a locked device`, `Force all packages as installed via Google Play Store`,
  `blocking non-sense root checks` (libcore), `ADB connection timeout 2 weeks`, `seccomp even if permissive`.
- **Funkcje GrapheneOS dla wielu użytkowników / hasło przymusu (duress) / Private Space w kontach
  pomocniczych**: głęboko w `frameworks/base`, `vold`, `Settings`, `Telephony` — setki linii i największe
  ryzyko konfliktów. Sensowne tylko w komplecie z GrapheneOS.
- **Motywy i wygląd** (zaokrąglenia, Material 3 Expressive, ikony, animacje Pixel): subiektywne, konfliktowe.
- **WebView Tomoms** (Calyx/AOSmium/Cromite, prywatne Trichrome): już dziś używamy prebuiltu LineageOS.

## Decyzje (25.09) i stan wdrożenia — przepis 0.2.0

| Obszar | Decyzja | Patche |
|---|---|---|
| Jądro | fork Tomoms + KSU-Next, scalany z LOS przy buildzie | krok w `ham.yml` |
| Drzewa urządzenia | wszystkie 27 commitów Tomoms (w tym DT2W) | `device_motorola_rhode` 9, `device_motorola_sm6225-common` 18 |
| Play Integrity | PIHooks + KeyboxImitation w obrazie (stan jak dziś na telefonie) | `frameworks_base` 21, `bionic` 1, `build_soong` 1, `system_core` 10 |
| Sieć + bionic (GrapheneOS) | tak | `system_netd` 3, `packages_modules_{Connectivity 8, NetworkStack 2, CaptivePortalLogin 1, Wifi 2}`, `packages_apps_Settings` 2, `frameworks_base` 8 (w tym `ConnectivityUtil`, której wymagają patche VPN lockdown), `bionic` 22 (z cache pliku hosts — ważne przy naszym dużym `/system/etc/hosts`), `tools_metalava` 1 (nowe API bez flag aconfig — bez tego lint `UNFLAGGED_API` zatrzymałby build) |
| Wyłączanie Wi-Fi/BT po czasie | tak | `frameworks_base` 2, `Wifi` 1, `Bluetooth` 1, `Settings` 1 (złożony ręcznie, z polskimi napisami) |
| Nagrywanie rozmów (auto) | tak | `packages_apps_Dialer` 10 |
| **Pakiet wydajnościowy** | tak — priorytet builda | patrz niżej |
| Limit ładowania 50%, zrzut 3 palcami, reszta funkcji | nie | — |

Każda seria nakłada się na LOS `lineage-23.2` z 25.09 i daje drzewo identyczne jak cherry-pick
(sprawdzone `git apply --cached` + porównanie drzew). Zależności między repozytoriami sprawdzone po importach i
stałych dodawanych przez patche; **kompilacja nie była jeszcze sprawdzona** — pierwszy build w HAM to weryfikuje. Dwa konflikty rozwiązane ręcznie i opisane w treści commitów:
`KeyboxChainGenerator: Use real vbmeta digest` (Settings.java) i ustawienia wyłączania Wi-Fi/BT.

## Pakiet wydajnościowy (25.09, druga runda)
Wszystko to Tomoms uruchamia na tym samym telefonie na co dzień, więc stabilność jest sprawdzona w praktyce;
ryzykiem jest tylko utrzymanie (więcej patchy = więcej miejsc na konflikt przy aktualizacji LOS).

| Obszar | Co | Patche |
|---|---|---|
| Alokator | jemalloc zamiast scudo (bionic, build/make, soong, debuggerd), krótszy decay, nowszy jemalloc z yaap (`rhode.xml`) | 4 serie + manifest |
| libc / libm | Arm Optimized Routines z yaap (memcpy/strlen/…), memset SIMD, `-O3`, LTO libm, fmodf, `-ffp-contract=fast` | `bionic` 11 + manifest |
| Kompilator | `-O3` domyślnie, unified LTO, limity instrukcji LTO, AFDO, FMA; bez clang-tidy i sprawdzeń ABI (szybszy build) | `build_soong` 22 |
| ART | optymalizacja całego ART, bez śledzenia i kontroli debug, dexopt w tle przy starcie i na 2 wątkach, `bg-dexopt=speed` (pełna kompilacja AOT aplikacji w tle), bez minidebuginfo | `art` 21, `build_make` 10, `vendor_lineage` 14 |
| Grafika / płynność | SurfaceFlinger: heurystyka odświeżania, touch boost, agresywniejszy idle, `-O3`; hwui `-O3`/ThinLTO, większy cache shaderów, polityka low-RAM | `frameworks_native` 42, część `frameworks_base` |
| system_server / SystemUI | ~190 zmian: mniej debug/logów/event logu, HashMap zamiast ArrayMap, buforowanie w WindowManagerze, mniej pracy przy przewijaniu powiadomień i QS, kompakcja pamięci procesów w tle, USAP (szybszy start aplikacji) | `frameworks_base` 194 |
| Launcher3 | mniej alokacji na klatkę, szybsza lista aplikacji, bez logów do pliku | `packages_apps_Launcher3` 13 |
| Reszta | flagi SQLite, init.rc bez zbędnych usług statystyk, priorytety kamery/mediów | `external_sqlite` 3, `system_core` 9, `frameworks_av` 4 |

Własne, ponad to, co ma Tomoms (decyzja 25.09):
- `system_server` kompilowany `speed` zamiast `speed-profile` (`patches/vendor_lineage/0015`) — szybszy system kosztem
  trochę RAM i miejsca;
- jądro (fork `16.2-ksun`, `moto-bengal.config`): zram **lz4** zamiast zstd (jądro Tomoms ma lz4 w asm ARMv8) i
  **CFI wyłączone** (kilka % na wywołaniach pośrednich, kosztem ochrony przed exploitami jądra).

Świadomie pominięte mimo „wydajnościowych” nazw:
- łańcuch `releaseMemory` (5 commitów: zabijanie procesów w tle przy wybudzeniu/wygaszeniu ekranu) — na słabym CPU
  oznacza więcej zimnych startów aplikacji, czyli wolniej przy przełączaniu; do tego konfliktowy;
- `Prevent system_server from restarting due to app issues` — maskuje błędy zamiast przyspieszać;
- „Axion hooks/service injector” — infrastruktura cudzego ROM-u bez własnego efektu.
Przy buildzie: `-O3` i LTO wydłużają kompilację (szacunkowo +15–25% czasu = kosztu serwera).

## Co się zmieniło w przepisie
1. `repo init -u https://github.com/LineageOS/android -b lineage-23.2`.
2. `rhode.xml`: drzewa urządzenia z LineageOS (`lineage-23.2`), jądro nadal `MikolajQ/...@16.2-ksun`.
3. Krok „Jądro: scalenie z LineageOS lineage-23.2” (konflikt = stop).
4. `apply-patches.sh`: serie `format-patch` przez `git am -3`, zwykłe diffy przez `git apply`; pierwszy błąd = stop.
5. `vendor/extra` instaluje `additional_repos.xml` F-Droid/Droid-ify (robił to `vendor/lineage` Tomoms);
   usunięty patch `vendor_lineage/0001-drop-private-trichrome` (dotyczył tylko jego `vendor/lineage`).
6. `scripts/check-patches.sh` (wołany ze `staleness.sh`): czy patche wchodzą na aktualny LOS i czy jądro scala się
   czysto — lokalnie, ~1,5 min, bez pobierania źródeł.

## Odświeżanie patcha, który przestał wchodzić
Narzędzia w `~/build/tomoms-audit`: `audit.sh` (klony bez plików, listy `out/*.own`), `port.sh <repo> sel/<repo>`
(cherry-pick na aktualny LOS przez `git merge-tree`, bez worktree), `resolve.sh` (ręczne rozwiązanie konfliktu),
potem `git format-patch --zero-commit refs/up^{commit}..refs/port` do `patches/<repo>/`. Listy wybranych commitów:
`~/build/tomoms-audit/sel/`. Najpierw sprawdzić, czy Tomoms nie poprawił już tego samego u siebie.

## Koszt utrzymania
Przy ~130 patchach, głównie małych i konfiguracyjnych, spodziewam się 0–3 konfliktów miesięcznie — najczęściej
w `frameworks_base` i `packages_apps_Settings`.

## Ryzyko przy pierwszej instalacji
Zmiana frameworka z Tomoms na LOS przy zachowaniu danych (bez „Format data”) zwykle działa, bo to ta sama
wersja Androida i te same klucze, ale nie jest gwarantowana — ustawienia funkcji Tomoms, których nie przenieśliśmy,
zostaną osierocone. Przed pierwszą instalacją: kopia zapasowa; pierwszą instalację robić ręcznie (sideload), nie przez OTA.
