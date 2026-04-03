#!/bin/bash
set -euo pipefail

# Generic iOS build + TestFlight upload script
# Called by the daemon for each deploy job.

REPO_PATH="$1"
SCHEME="$2"
PROJECT="$3"        # can be empty
WORKSPACE="$4"      # can be empty
API_KEY_ID="$5"
API_ISSUER="$6"
API_KEY_PATH="$7"
TEAM_ID="$8"
BUMP_BUILD="$9"
BRANCH="${10:-}"

ARCHIVE_PATH="/tmp/ios-deploy-${SCHEME}-$$.xcarchive"
EXPORT_PATH="/tmp/ios-deploy-${SCHEME}-$$-export"
DAEMON_DIR="$(cd "$(dirname "$0")/.." && pwd)"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

cleanup() {
    rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "/tmp/ios-deploy-${SCHEME}-$$-ExportOptions.plist"
}
trap cleanup EXIT

cd "$REPO_PATH"

# Checkout branch if specified
if [[ -n "$BRANCH" ]]; then
    log "Checking out branch: $BRANCH"
    git fetch origin "$BRANCH" --quiet 2>/dev/null || true
    git checkout "$BRANCH" --quiet 2>/dev/null || git checkout "origin/$BRANCH" --quiet
    git pull --quiet 2>/dev/null || true
fi

# Auto-detect project/workspace if not specified
if [[ -z "$PROJECT" && -z "$WORKSPACE" ]]; then
    if ls *.xcworkspace 1>/dev/null 2>&1; then
        WORKSPACE=$(ls -1 *.xcworkspace | head -1)
        log "Auto-detected workspace: $WORKSPACE"
    elif ls *.xcodeproj 1>/dev/null 2>&1; then
        PROJECT=$(ls -1 *.xcodeproj | head -1)
        log "Auto-detected project: $PROJECT"
    else
        log "ERROR: No .xcodeproj or .xcworkspace found in $REPO_PATH"
        exit 1
    fi
fi

# Build the xcodebuild base args
BUILD_ARGS=()
if [[ -n "$WORKSPACE" ]]; then
    BUILD_ARGS+=(-workspace "$WORKSPACE")
else
    BUILD_ARGS+=(-project "$PROJECT")
fi
BUILD_ARGS+=(-scheme "$SCHEME")

# Bump build number if requested
if [[ "$BUMP_BUILD" == "True" || "$BUMP_BUILD" == "true" ]]; then
    log "Bumping build number..."
    # Find the project file
    local_project="$PROJECT"
    [[ -z "$local_project" ]] && local_project=$(ls -1 *.xcodeproj 2>/dev/null | head -1)
    if [[ -n "$local_project" ]]; then
        CURRENT=$(grep -A1 'CURRENT_PROJECT_VERSION' "$local_project/project.pbxproj" | grep -o '[0-9]*' | head -1 || echo "1")
        NEXT=$((CURRENT + 1))
        log "Build number: $CURRENT → $NEXT"
        sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT/CURRENT_PROJECT_VERSION = $NEXT/g" "$local_project/project.pbxproj"
    fi
fi

# Create ExportOptions.plist
EXPORT_PLIST="/tmp/ios-deploy-${SCHEME}-$$-ExportOptions.plist"
cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

AUTH_ARGS=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$API_KEY_PATH"
    -authenticationKeyID "$API_KEY_ID"
    -authenticationKeyIssuerID "$API_ISSUER"
)

# Step 1: Archive
log "Archiving $SCHEME..."
xcodebuild \
    "${BUILD_ARGS[@]}" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    "${AUTH_ARGS[@]}" \
    -quiet \
    || { log "ERROR: Archive failed"; exit 1; }

log "Archive succeeded ✓"

# Step 2: Export & Upload
log "Exporting and uploading to TestFlight..."
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$EXPORT_PATH" \
    "${AUTH_ARGS[@]}" \
    || { log "ERROR: Export/upload failed"; exit 1; }

log "Upload succeeded ✓"
log "Build will appear in TestFlight after Apple processes it (5-15 min)"
