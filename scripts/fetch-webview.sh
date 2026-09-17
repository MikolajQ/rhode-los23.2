#!/usr/bin/env bash
# Cromite SystemWebView jako jedyny WebView w obrazie. APK ma 291 MB (limit GitHuba: 100 MB),
# więc nie trzymamy go w gicie — pobieramy z release'u Cromite z przypiętym tagiem i SHA-256.
# Aktualizacja: podmienić TAG i SHA256 (digest jest w API GitHuba: releases/latest -> assets[].digest).
# Wymaga w vendor/extra: PRODUCT_PACKAGES += CromiteWebView oraz overlay config_webview_packages.xml
# z packageName="org.cromite.webview" (Cromite buduje webview pod tą nazwą, nie com.android.webview).
set -euo pipefail
ROOT=${1:?korzeń drzewa}
TAG="v153.0.8010.37-11507ac1061b5ea227806f5e84db5a57df6ccf6a"
SHA256="dcb233a86d58ca922f8aa08dd4216c9158450866286d727a1358e502e935baa3"
URL="https://github.com/uazo/cromite/releases/download/$TAG/arm64_SystemWebView.apk"
DEST="$ROOT/external/chromium-webview"
mkdir -p "$DEST"
[ -s "$DEST/webview64.apk" ] || curl -fL --retry 3 -o "$DEST/webview64.apk" "$URL"
echo "$SHA256  $DEST/webview64.apk" | sha256sum -c -
cat > "$DEST/Android.bp" <<'BP'
// Cromite SystemWebView (org.cromite.webview), pobierany przez scripts/fetch-webview.sh.
android_app_import {
    name: "CromiteWebView",
    product_specific: true,
    presigned: true,
    preprocessed: true,
    optional_uses_libs: ["android.test.base", "androidx.window.extensions", "android.ext.adservices"],
    overrides: ["webview"],
    arch: {
        arm64: {
            apk: "webview64.apk",
        },
    },
    required: [
        "libwebviewchromium_loader",
        "libwebviewchromium_plat_support",
    ],
}
BP
echo "webview: $DEST/webview64.apk ($(du -m "$DEST/webview64.apk" | cut -f1) MB), $TAG"
