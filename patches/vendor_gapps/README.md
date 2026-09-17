# Patche na MindTheGapps (gałąź baklava)

Nakładane przez `scripts/apply-patches.sh` po `repo sync`, `git apply` na `vendor/gapps`.
Wygenerowane z realnego drzewa `baklava` @f8cdcff (2026-06-12); po zmianach upstreamu: `git apply --check`,
w razie konfliktu wygenerować na nowo (`git diff` na sklonowanym MTG).

## 0001-prune-to-core.patch — zestaw jak NikGapps core + Android Auto

Wycięte (~385 MB): `Velvet` (242 MB), `SpeechServicesByGoogle` (66), `talkback` (34), `Wellbeing` + `wellbeing.xml` (22),
`GoogleRestore` (15), `MarkupGoogle_v2` (6), `AndroidAutoStub` (pełny Gearhead przychodzi z gapps-extras),
`GoogleFeedback`, `PrebuiltExchange3Google`, `com.google.android.dialer.support(.xml)`, `libjni_latinimegoogle`.

Zostają: `GmsCore`, `Phonesky`, `GoogleServicesFramework`, `GooglePartnerSetup`, `SetupWizard` (na czas dodawania konta
dziecka; można wyciąć później), `GoogleCalendarSyncAdapter` + `GoogleContactsSyncAdapter` (3 MB, synchronizacja kontaktów
konta Google — WhatsApp z nich korzysta), wszystkie XML-e (permissions, sysconfig, default-permissions, hiddenapi),
`gapps.rc`, `gms_fsverity_cert.der`, overlaye `Gms*Overlay`.

`privapp-permissions-google-product.xml` zawiera blok `com.google.android.gms.supervision` — allowlist dla
GmsSupervision z gapps-extras; nie ruszać.
