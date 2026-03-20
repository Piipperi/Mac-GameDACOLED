#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GameDACOLED"
PRODUCT_NAME="GameDAC OLED Controller"
BUILD_DIR="$ROOT_DIR/.app-build"
APP_DIR="$ROOT_DIR/dist/$PRODUCT_NAME.app"
CONST_VALUES_DIR="$BUILD_DIR/appintents"
CONST_VALUES_FILE="$CONST_VALUES_DIR/Shortcuts.swiftconstvalues"
CONST_VALUES_LIST="$CONST_VALUES_DIR/const-values.list"
SOURCE_LIST="$ROOT_DIR/.build/arm64-apple-macosx/release/GameDACOLED.build/sources"
METADATA_DEPENDENCY_LIST="$CONST_VALUES_DIR/dependency-metadata.list"
METADATA_OUTPUT_DIR="$CONST_VALUES_DIR/processed"
SDK_ROOT="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk"
TOOLCHAIN_DIR="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
XCODE_BUILD_VERSION="$(xcodebuild -version | awk '/Build version/ { print $3 }')"

mkdir -p "$BUILD_DIR/clang-module-cache" "$BUILD_DIR/swiftpm-cache" "$BUILD_DIR/swiftpm-config"

cd "$ROOT_DIR"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache" \
SWIFTPM_CACHE_PATH="$BUILD_DIR/swiftpm-cache" \
SWIFTPM_CONFIG_PATH="$BUILD_DIR/swiftpm-config" \
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_DIR/Contents/Info.plist"

rm -rf "$CONST_VALUES_DIR"
mkdir -p "$CONST_VALUES_DIR" "$METADATA_OUTPUT_DIR"

cat > "$CONST_VALUES_DIR/const_extract_protocols.json" <<'EOF'
["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding","AppShortcutsProvider","AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider"]
EOF

swiftc -frontend -c \
    -primary-file "$ROOT_DIR/Sources/GameDACOLED/Shortcuts.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/AppModel.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/AppSettings.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/AudioVisualizerCapture.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/ContentView.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/ExternalModeControl.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/GIFLoader.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/GameDACOLEDApp.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/GameSenseClient.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/ImageRenderer.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/MenuBarView.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/SystemStatsMonitor.swift" \
    "$ROOT_DIR/Sources/GameDACOLED/VisualizerGainField.swift" \
    -module-name "$APP_NAME" \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK_ROOT" \
    -F /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
    -F /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks \
    -I /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib \
    -L /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib \
    -const-gather-protocols-file "$CONST_VALUES_DIR/const_extract_protocols.json" \
    -emit-const-values-path "$CONST_VALUES_FILE" \
    -emit-module-path "$CONST_VALUES_DIR/Shortcuts.partial.swiftmodule" \
    -serialize-diagnostics-path "$CONST_VALUES_DIR/Shortcuts.dia" \
    -emit-dependencies-path "$CONST_VALUES_DIR/Shortcuts.d" \
    -o "$CONST_VALUES_DIR/Shortcuts.o"

printf '%s\n' "$CONST_VALUES_FILE" > "$CONST_VALUES_LIST"
: > "$METADATA_DEPENDENCY_LIST"

xcrun appintentsmetadataprocessor \
    --output "$METADATA_OUTPUT_DIR" \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name "$APP_NAME" \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_BUILD_VERSION" \
    --platform-family macOS \
    --deployment-target 13.0 \
    --target-triple arm64-apple-macosx13.0 \
    --source-file-list "$SOURCE_LIST" \
    --swift-const-vals-list "$CONST_VALUES_LIST" \
    --metadata-file-list "$METADATA_DEPENDENCY_LIST" \
    --force-metadata-output

if [ -d "$METADATA_OUTPUT_DIR/Metadata.appintents" ]; then
    cp -R "$METADATA_OUTPUT_DIR/Metadata.appintents" "$APP_DIR/Contents/Resources/Metadata.appintents"
fi

echo "Built app bundle at: $APP_DIR"
