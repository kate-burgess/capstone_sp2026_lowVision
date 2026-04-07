#!/usr/bin/env bash
set -euo pipefail

# Vercel build environment does not include Flutter by default.
# This script installs Flutter (stable) and builds the web bundle to build/web.

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_DIR="${FLUTTER_DIR:-/tmp/flutter}"

if [ ! -d "$FLUTTER_DIR" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version

flutter config --enable-web
flutter pub get

# Build for Flutter web. (Default renderer is fine; override via env if desired.)
BASE_HREF="${FLUTTER_BASE_HREF:-/}"
flutter build web --release --base-href "$BASE_HREF"

