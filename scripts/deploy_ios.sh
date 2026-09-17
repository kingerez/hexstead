#!/bin/bash
# Builds, signs, and uploads Hexstead to TestFlight.
#
# Usage: scripts/deploy_ios.sh <build-number>
#
# Requires (one-time setup already done on this machine):
#  - ASC API key at ~/private_keys/AuthKey_FU25H9M283.p8
#  - Distribution cert + key in the hexstead-ci.keychain
#  - "Hexstead AppStore" provisioning profile installed
set -euo pipefail

BUILD_NUMBER="${1:?usage: deploy_ios.sh <build-number>}"
KEY_ID="FU25H9M283"
ISSUER_ID="0106418d-f931-4867-bccc-22730ea261c0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
flutter build ios --release --no-codesign --build-number="$BUILD_NUMBER"

cd ios
security unlock-keychain -p "$(cat build/kc_pw.txt)" hexstead-ci.keychain

xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Runner.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | grep -E '\*\* ARCHIVE'

xcodebuild -exportArchive -archivePath build/Runner.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/ipa \
  | grep -E '\*\* EXPORT'

xcrun altool --upload-app -f build/ipa/hexstead.ipa -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID" 2>&1 | tail -4
