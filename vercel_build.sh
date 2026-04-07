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

# Pass backend URL at *build time* so `String.fromEnvironment('OCR_BASE_URL')` works.
# Vercel Environment Variables are available here as shell env vars, but they are NOT
# available to Dart at runtime in the browser unless we pass --dart-define.
OCR_BASE_URL_VALUE="${OCR_BASE_URL:-}"

if [ -z "$OCR_BASE_URL_VALUE" ]; then
  echo "ERROR: OCR_BASE_URL is not set in the build environment."
  echo "Set it in Vercel Project Settings → Environment Variables, then redeploy."
  exit 1
fi

flutter build web --release \
  --base-href "$BASE_HREF" \
  --dart-define=OCR_BASE_URL="$OCR_BASE_URL_VALUE"

