#!/bin/bash
set -euo pipefail

# YMoney TestFlight Deploy Script
# Usage: ./scripts/deploy-testflight.sh [--bump-build]
#
# Prerequisites:
#   1. App Store Connect API key at ./private_keys/AuthKey_HMJML9G967.p8
#   2. Apple Distribution certificate in keychain
#   3. App registered in App Store Connect (net.codekind.ymoney)
#
# Run from a normal Terminal (not a sandboxed environment) so that
# Xcode's ITunesSoftwareService XPC daemon is available.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCHEME="YMoney"
PROJECT="$PROJECT_DIR/YMoney.xcodeproj"
ARCHIVE_PATH="/tmp/YMoney.xcarchive"
EXPORT_PATH="/tmp/YMoney_export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"

# App Store Connect API Key
API_KEY_ID="HMJML9G967"
API_ISSUER="ed1c4be0-e08c-444f-91a4-88a8dc523cf9"
API_KEY_PATH="$PROJECT_DIR/private_keys/AuthKey_${API_KEY_ID}.p8"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}▸${NC} $1"; }
warn() { echo -e "${YELLOW}▸${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

# Validate prerequisites
[[ -f "$API_KEY_PATH" ]] || fail "API key not found at $API_KEY_PATH"
[[ -f "$EXPORT_OPTIONS" ]] || fail "ExportOptions.plist not found at $EXPORT_OPTIONS"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Distribution" \
    || fail "No Apple Distribution certificate found in keychain"

# Optional: bump build number
if [[ "${1:-}" == "--bump-build" ]]; then
    CURRENT=$(grep -A1 'CURRENT_PROJECT_VERSION' "$PROJECT/project.pbxproj" | grep -o '[0-9]*' | head -1)
    NEXT=$((CURRENT + 1))
    log "Bumping build number: $CURRENT → $NEXT"
    sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT/CURRENT_PROJECT_VERSION = $NEXT/g" "$PROJECT/project.pbxproj"
fi

# Step 1: Archive
log "Archiving $SCHEME..."
rm -rf "$ARCHIVE_PATH"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER" \
    -quiet \
    || fail "Archive failed"

log "Archive succeeded ✓"

# Step 2: Export & Upload to TestFlight
log "Exporting and uploading to TestFlight..."
rm -rf "$EXPORT_PATH"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER" \
    || fail "Export/upload failed"

log "Upload succeeded ✓"
log "Build will appear in TestFlight after Apple's processing (5-15 min)"

# Cleanup
rm -rf "$ARCHIVE_PATH"
log "Done!"
