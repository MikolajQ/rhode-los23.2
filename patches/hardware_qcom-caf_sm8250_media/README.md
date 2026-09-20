# Patche na LineageOS/android_hardware_qcom_media @lineage-23.2-caf-sm8250

Dla `TARGET_BOARD_PLATFORM := bengal` LineageOS mapuje HAL mediów na wariant `sm8250`
(`hardware/qcom-caf/common/BoardConfigQcom.mk`, `UM_4_19_FAMILY`). `libOmxVenc.so` buduje się z tego
drzewa (TheMuppets nie dostarcza go jako bloba). Wygenerowane z `de3a6cf` (2026-09-20).

## 0001-venc-advertise-full-level-range-clamp-on-set.patch — wideo w GCam (LMC 8.4) i innych apkach żądających poziomu

Sterownik `msm_vidc` dla bengal (`bengal_capabilities_v0/v1` w kernelu) deklaruje enkoder H.264 do Level 5.0
i HEVC do Level 5 (1080p30). `venc_get_supported_profile_level()` zwraca ten poziom jako `eLevel`, a
`ACodec::verifySupportForProfileAndLevel()` odrzuca całą konfigurację, gdy aplikacja prosi o wyższy —
GCam prosi o 5.1+ nawet dla 1080p30 → `configureCodec -61` (H.264) i aplikacja wisi na czarnym ekranie.
Dla HEVC dodatkowo zapytanie o profil Main10 zwracało `OMX_ErrorHardware` (HDR wyłączone), co przerywa
enumerację zamiast ją zakończyć.

Zmiany:
- `eLevel` = pełny zakres (`OMX_VIDEO_AVCLevel62` / `OMX_VIDEO_HEVCHighTierLevel62`) w odpowiedzi na
  `OMX_IndexParamVideoProfileLevelQuerySupported`;
- `venc_set_level()` przycina żądany poziom do `VIDIOC_QUERYCTRL(...).maximum` sterownika — strumień
  1080p30 mieści się w Level 5.0, więc `level_idc` w SPS jest poprawny;
- Main10/HDR10 przy wyłączonym HDR → `OMX_ErrorNoMore` zamiast `OMX_ErrorHardware`.

Zdiagnozowane 2026-09-20 na telefonie: `logcat` (OMX-VENC `v4l2 profile … flags 131095`, `get_supported_profile_level 2, 32768`),
`screenrecord` (Baseline/L1) i GCam MGC działały, LMC 8.4 nie. Bez wpływu na dekodowanie.
