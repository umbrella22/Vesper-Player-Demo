#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-release}"

if [[ "$PROFILE" != "debug" && "$PROFILE" != "release" ]]; then
  echo "Unsupported profile: $PROFILE" >&2
  echo "Usage: $0 [debug|release]" >&2
  exit 1
fi

CONFIGURATION="Release"
if [[ "$PROFILE" == "debug" ]]; then
  CONFIGURATION="Debug"
fi

export VESPER_APPLE_FFMPEG_PROFILE="${VESPER_APPLE_FFMPEG_PROFILE:-remux-local}"

bash "$ROOT_DIR/scripts/prepare_ios_build.sh"

(
  cd "$ROOT_DIR/third_party/vesper-player-sdk"
  bash scripts/ios/build-player-ffi-xcframework.sh "$PROFILE"
)

xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination generic/platform=iOS \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
