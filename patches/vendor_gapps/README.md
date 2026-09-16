# Patche na MindTheGapps (gałąź baklava)

Nakładane przez `scripts/apply-patches.sh` po `repo sync`, `git apply` na `vendor/gapps`.
Generować z realnego drzewa: `git -C vendor/gapps diff > 0001-prune-to-core.patch`.

Do wycięcia (zestaw ma odpowiadać NikGapps core + Android Auto):

- `arm64/arm64-vendor.mk`: `MarkupGoogle_v2`, `SpeechServicesByGoogle`, `Velvet`, `talkback`, `libjni_latinimegoogle`
  (zostają: `GmsCore`, `Phonesky`; `SetupWizard` — decyzja: zostawić na czas dodawania konta dziecka, potem można wyciąć)
- `common/common-vendor.mk`: `AndroidAutoStub` (zastępuje go pełny Gearhead z gapps-extras), `GoogleCalendarSyncAdapter`,
  `GoogleContactsSyncAdapter`, `GoogleFeedback`, `PrebuiltExchange3Google`, `com.google.android.dialer.support*`,
  `GoogleRestore`, `Wellbeing`, `wellbeing.xml`
- zostają w całości: `GoogleServicesFramework`, `GooglePartnerSetup`, wszystkie `*.xml` (permissions, sysconfig,
  default-permissions, hiddenapi), `gapps.rc`, `gms_fsverity_cert.der`, overlaye `Gms*Overlay`

Uwaga: `privapp-permissions-google-product.xml` zawiera blok `com.google.android.gms.supervision` —
nie ruszać, to allowlist dla GmsSupervision z gapps-extras.
