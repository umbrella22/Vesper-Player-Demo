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

XCCONFIG_PATH="$ROOT_DIR/ios/Flutter/$CONFIGURATION.xcconfig"
IOS_DEPLOYMENT_TARGET="$(
  sed -n \
    's/^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\)[[:space:]]*$/\1/p' \
    "$XCCONFIG_PATH" \
    | tail -n 1
)"
if [[ -z "$IOS_DEPLOYMENT_TARGET" ]]; then
  echo "Failed to resolve IPHONEOS_DEPLOYMENT_TARGET from $XCCONFIG_PATH" >&2
  exit 1
fi

export VESPER_APPLE_FFMPEG_PROFILE="${VESPER_APPLE_FFMPEG_PROFILE:-remux-local}"

XCODEBUILD_ARGS=(
  -workspace ios/Runner.xcworkspace
  -scheme Runner
  -configuration "$CONFIGURATION"
  -sdk iphoneos
  -destination generic/platform=iOS
)
if [[ -n "${VESPER_IOS_DERIVED_DATA_PATH:-}" ]]; then
  mkdir -p "$VESPER_IOS_DERIVED_DATA_PATH"
  XCODEBUILD_ARGS+=(
    -derivedDataPath "$VESPER_IOS_DERIVED_DATA_PATH"
  )
fi

bash "$ROOT_DIR/scripts/prepare_ios_build.sh"

(
  cd "$ROOT_DIR/third_party/vesper-player-sdk"
  bash scripts/ios/build-player-ffi-xcframework.sh "$PROFILE"
)

# Flutter resolves local Swift packages during --config-only. The Rust binary
# target above must exist before this step runs on a clean checkout.
(
  cd "$ROOT_DIR"
  flutter build ios \
    --config-only \
    --no-codesign \
    --no-pub \
    "--$PROFILE"
)

(
  cd "$ROOT_DIR"
  xcodebuild \
    "${XCODEBUILD_ARGS[@]}" \
    IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
)
