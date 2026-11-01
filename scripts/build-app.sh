#!/usr/bin/env bash
# Builds "HCG RePrompter.app" locally from the Swift package.
#
# Usage: scripts/build-app.sh [debug|release]
#
# The bundle is ad-hoc signed ("-") for local use only. It is NOT signed with a
# Developer ID, NOT notarized and NOT distributed — release decisions remain
# with the founder (see docs/RELEASE.md).
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="HCG RePrompter"
EXECUTABLE="RePrompter"
BUNDLE_ID="com.hakmicapital.reprompter"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' "$ROOT/Sources/RePrompterCore/AppInfo.swift")"
BUILD="$(sed -n 's/.*static let build = "\(.*\)".*/\1/p' "$ROOT/Sources/RePrompterCore/AppInfo.swift")"
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: the application bundle can only be built on macOS." >&2
  exit 1
fi

echo "==> Building $EXECUTABLE ($CONFIG)"
swift build --package-path "$ROOT" -c "$CONFIG" --product "$EXECUTABLE"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

# Brand artwork: copied directly into Resources (looked up by BrandAssets).
cp "$ROOT/Sources/RePrompterUI/Resources/"*.png "$APP/Contents/Resources/"

ICON_KEY=""
if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ROOT/Branding/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
  echo "warning: iconutil not found; the bundle will use the runtime icon only." >&2
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  $ICON_KEY
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Hakmi Capital Group. Pre-release development build.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing for local use"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Done: $APP"
