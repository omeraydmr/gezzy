#!/bin/zsh
# Gezzy'yi Release (production sunucusu) olarak derler, kayıtlı cihazlara kurulabilir IPA çıkarır
# ve istenirse bağlı iPhone'a kurar.
#   scripts/release.sh            → ios/dist/Gezzy.ipa
#   scripts/release.sh --install  → ayrıca bağlı ilk fiziksel iPhone'a kurar ve açar
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE=build/Gezzy.xcarchive
DIST=dist

xcodegen generate >/dev/null
rm -rf "$ARCHIVE" "$DIST"
xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates archive | grep -E "error:|ARCHIVE" || true
[ -d "$ARCHIVE" ] || { echo "Arşiv oluşmadı"; exit 1; }

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
