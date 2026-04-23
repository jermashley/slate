#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXECUTABLE="$ROOT_DIR/.build/arm64-apple-macosx/debug/Slate"

cd "$ROOT_DIR"

if [[ "${1:-}" == "--rebuild" || ! -x "$APP_EXECUTABLE" ]]; then
  swift build
fi

exec "$APP_EXECUTABLE"
