# Patche na Tomoms/android_build @16.2 (build/make)

- `0001-drop-etc_hosts.patch` — usuwa `etc_hosts` z `PRODUCT_PACKAGES` w `target/product/base_system.mk`.
  Nasz `hosts_rhode` (vendor/extra) ma `overrides: ["etc_hosts"]`, ale soong i tak generuje regułę instalacji
  `system/etc/hosts` dla obu modułów i kati pada na „overriding commands for target". Bez etc_hosts zostaje jeden.
