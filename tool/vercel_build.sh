#!/usr/bin/env bash
# Builds the web version on Vercel (see vercel.json). Vercel has no Flutter,
# so the install step fetches a pinned Flutter release first.
#
#   bash tool/vercel_build.sh install   # get Flutter and the packages
#   bash tool/vercel_build.sh build     # build/web, with WebAssembly and a JS fallback
#
# It also works on any Linux machine: set FLUTTER_ROOT to use a Flutter you
# already have.
set -euo pipefail

FLUTTER_VERSION="3.47.8"
cd "$(dirname "$0")/.."
SDK="${FLUTTER_ROOT:-$PWD/.flutter-sdk}"
export PATH="$SDK/bin:$PATH"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true

install() {
  if [ ! -x "$SDK/bin/flutter" ]; then
    # Flutter unzips its Dart SDK on the first run
    command -v unzip >/dev/null 2>&1 || dnf install -y unzip >/dev/null
    echo "Getting Flutter $FLUTTER_VERSION"
    git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$SDK"
  fi
  git config --global --add safe.directory "$SDK"
  flutter config --no-analytics >/dev/null
  flutter --version
  flutter pub get
}

build() {
  flutter build web --release --wasm
  # debug symbols for the engine are never loaded by the game
  find build/web/canvaskit -name '*.symbols' -delete
  echo "Built $(du -sh build/web | cut -f1) into build/web"
}

case "${1:-}" in
  install) install ;;
  build) build ;;
  *)
    install
    build
    ;;
esac
