#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
APP_DIR="$ROOT_DIR/dist/Slate.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PKGINFO_PATH="$APP_DIR/Contents/PkgInfo"
EXECUTABLE_PATH="$BUILD_DIR/Slate"
BUILD_FIRST=1

for arg in "$@"; do
  case "$arg" in
    --no-build)
      BUILD_FIRST=0
      ;;
    --rebuild)
      BUILD_FIRST=1
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ "$BUILD_FIRST" -eq 1 ]]; then
  swift build
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/Slate"
cp "$ROOT_DIR/Support/Slate-Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$PKGINFO_PATH"

for bundle_path in "$BUILD_DIR"/*.bundle; do
  if [[ -d "$bundle_path" ]]; then
    cp -R "$bundle_path" "$RESOURCES_DIR/"
  fi
done

chmod +x "$MACOS_DIR/Slate"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
