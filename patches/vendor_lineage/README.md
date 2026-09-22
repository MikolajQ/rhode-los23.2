# Patche na Tomoms/android_vendor_lineage @16.2

- `0001-drop-private-trichrome.patch` — jego `config/common.mk` dodaje `TrichromeLibrary`, `TrichromeWebView`,
  `TrichromeChrome` do `PRODUCT_PACKAGES`. Te moduły pochodzą z nieopublikowanego repo (remote `private`
  w jego manifeście); bez nich `mka` zatrzymuje się na nieznanych modułach. Nie ma to związku z naszym WebView —
  dostarczamy go osobno, prebuiltem oficjalnym LineageOS (moduł `webview`, dodawany w `vendor/extra`; do 22.09 był
  to Cromite, patrz uazo/cromite#3085).

Po każdym jego merge'u z LineageOS: `git apply --check`; jeśli pada, wygenerować na nowo.
