#!/bin/bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
app_dir="$root_dir/WorkBar.app"
binary="$root_dir/.build/$configuration/WorkBar"

swift build --package-path "$root_dir" -c "$configuration" --product WorkBar
test -x "$binary"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary" "$app_dir/Contents/MacOS/WorkBar"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>WorkBar</string>
    <key>CFBundleDisplayName</key>
    <string>WorkBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.nxzhai.workbar</string>
    <key>CFBundleExecutable</key>
    <string>WorkBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>WorkBar 读取未完成提醒事项，将它们导入为今日工作任务。</string>
    <key>NSRemindersUsageDescription</key>
    <string>WorkBar 读取未完成提醒事项，将它们导入为今日工作任务。</string>
</dict>
</plist>
PLIST

# Keep the ad-hoc code identity stable across rebuilds so macOS can remember
# the Reminders permission for this bundle instead of binding it to each hash.
printf '%s\n' 'designated => identifier "com.nxzhai.workbar"' \
    | codesign --force --deep --sign - --requirements - "$app_dir"
echo "Built $app_dir"
