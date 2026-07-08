#!/bin/bash
# Archive Screen Test for the App Store and upload to App Store Connect,
# using the App Store Connect API key already on this machine.
#
# Prereqs (one-time, human):
#   - Apple Developer Program membership (paid) on the team that owns
#     com.btyt.screentest.
#   - Sign in with Apple enabled for the App ID (auto-registered by
#     -allowProvisioningUpdates on first run).
#
# Usage:
#   TEAM_ID=XXXXXXXXXX ISSUER_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
#     bash scripts/appstore_upload.sh
#
#   TEAM_ID   = the 10-char Apple Developer Team that owns the bundle id
#   ISSUER_ID = App Store Connect -> Users and Access -> Integrations ->
#               App Store Connect API -> Issuer ID (a UUID)
set -euo pipefail

: "${TEAM_ID:?Set TEAM_ID (10-char Apple Developer Team ID)}"
: "${ISSUER_ID:?Set ISSUER_ID (App Store Connect API Issuer ID)}"

KEY_ID="3S6925Y2PL"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
[ -f "$KEY_PATH" ] || { echo "API key not found at $KEY_PATH"; exit 1; }

cd "$(dirname "$0")/.."
ARCHIVE="build/ScreenTest.xcarchive"
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$KEY_ID"
      -authenticationKeyIssuerID "$ISSUER_ID")

echo "==> Regenerating project"
xcodegen generate

echo "==> Archiving (Release, automatic signing)"
xcodebuild -project GoalCraftiOS.xcodeproj -scheme GoalCraftiOS \
  -configuration Release -sdk iphoneos -archivePath "$ARCHIVE" archive \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  "${AUTH[@]}"

echo "==> Writing ExportOptions.plist"
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict>
</plist>
PLIST

echo "==> Exporting + uploading to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export "${AUTH[@]}"

echo "==> Done. Check App Store Connect -> TestFlight in a few minutes for the build."
