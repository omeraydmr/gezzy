#!/bin/zsh
# Gezzy'yi Release (production sunucusu) olarak derler, kayıtlı cihazlara kurulabilir IPA çıkarır
# ve istenirse bağlı iPhone'a kurar.
#   scripts/release.sh            → ios/dist/Gezzy.ipa
#   scripts/release.sh --install  → ayrıca bağlı ilk fiziksel iPhone'a kurar ve açar
#   scripts/release.sh --testflight → App Store Connect'e yükler (build numarası: yyyyMMddHHmm)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE=build/Gezzy.xcarchive
DIST=dist

xcodegen generate >/dev/null
rm -rf "$ARCHIVE" "$DIST"
BUILD_ARGS=()
# TestFlight her yüklemede daha büyük build numarası ister.
[[ "${1:-}" == "--testflight" ]] && BUILD_ARGS=(CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)")
xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates "${BUILD_ARGS[@]}" archive | grep -E "error:|ARCHIVE" || true
[ -d "$ARCHIVE" ] || { echo "Arşiv oluşmadı"; exit 1; }

if [[ "${1:-}" == "--testflight" ]]; then
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$DIST" \
    -exportOptionsPlist Config/ExportOptions-AppStore.plist -allowProvisioningUpdates | grep -E "error|EXPORT|Upload" || true
  echo "Yükleme bitti; build birkaç dakika içinde App Store Connect › TestFlight'ta görünür."
  exit 0
fi

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$DIST" \
  -exportOptionsPlist Config/ExportOptions.plist -allowProvisioningUpdates | grep -E "error|EXPORT" || true
[ -f "$DIST/Gezzy.ipa" ] || { echo "IPA oluşmadı"; exit 1; }
echo "IPA: $PWD/$DIST/Gezzy.ipa"

if [[ "${1:-}" == "--install" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep physical | grep iPhone | grep available | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
  [ -n "$DEVICE" ] || { echo "Bağlı iPhone bulunamadı"; exit 1; }
  xcrun devicectl device install app --device "$DEVICE" "$DIST/Gezzy.ipa" >/dev/null
  xcrun devicectl device process launch --device "$DEVICE" com.omeraydemir.gezzy >/dev/null
  echo "Kuruldu ve açıldı: $DEVICE"
fi
