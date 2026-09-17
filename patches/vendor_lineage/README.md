# Patche na Tomoms/android_vendor_lineage @16.2

- `0001-drop-private-trichrome.patch` — jego `config/common.mk` dodaje `TrichromeLibrary`, `TrichromeWebView`,
  `TrichromeChrome` do `PRODUCT_PACKAGES`. Te moduły pochodzą z nieopublikowanego repo (remote `private`
  w jego manifeście); bez nich `mka` zatrzymuje się na nieznanych modułach. WebView dostarczamy sami
  (`scripts/fetch-webview.sh`, moduł `CromiteWebView` dodawany w `vendor/extra`).

Po każdym jego merge'u z LineageOS: `git apply --check`; jeśli pada, wygenerować na nowo.
