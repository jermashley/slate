#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Slate.app"
ZIP_PATH="$DIST_DIR/Slate-mac-test.zip"

cd "$ROOT_DIR"
zsh "$ROOT_DIR/Scripts/package_app.sh" "$@"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$ZIP_PATH"
