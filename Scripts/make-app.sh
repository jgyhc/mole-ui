#!/usr/bin/env bash
# 将 SPM 可执行文件打包为 Mole.app（含 Info.plist）。
# 用法：Scripts/make-app.sh
set -euo pipefail

APP_NAME="Mole"
BINARY_NAME="Mole"
RELEASE_BIN=".build/release/$BINARY_NAME"
APP_BUNDLE="$APP_NAME.app"

echo "▸ swift build -c release"
swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 应用图标（从 asset catalog 取 1024px PNG，系统会自动缩放到各尺寸）
if [ -f "Sources/MoleApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png" ]; then
  cp "Sources/MoleApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Mole</string>
    <key>CFBundleDisplayName</key>
    <string>Mole</string>
    <key>CFBundleIdentifier</key>
    <string>dev.mole.ui</string>
    <key>CFBundleExecutable</key>
    <string>Mole</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>GPL-3.0 · 源自 tw93/Mole</string>
</dict>
</plist>
PLIST

echo "✅ 已生成 $APP_BUNDLE"
