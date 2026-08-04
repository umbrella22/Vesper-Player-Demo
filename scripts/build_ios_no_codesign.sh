#!/usr/bin/env bash
#
# 无签名构建 iOS 应用（debug/release）。本机开发与 CI 出包的统一入口：
#   bash scripts/build_ios_no_codesign.sh [debug|release]
#
# 流程：准备 Flutter 工作区（flutter pub get + SwiftPM 平台同步）
#   → 构建 SDK FFI xcframework → flutter build ios --config-only
#   → xcodebuild（关闭代码签名）。
#
# 部署目标从 ios/Flutter/<Configuration>.xcconfig 读取；如需自定义
# DerivedData，设置环境变量 VESPER_IOS_DERIVED_DATA_PATH。
# 被 .github/workflows/ios-release-ipa.yml 以 release 调用。
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

# 准备 Flutter 工作区（归档 stale 的 Swift package 链接、flutter pub get），
# 再把 iOS 部署目标同步到 Flutter 生成的 SwiftPM manifest。
bash "$ROOT_DIR/scripts/prepare_flutter_workspace.sh"
bash "$ROOT_DIR/scripts/sync_ios_swiftpm_platforms.sh" "$ROOT_DIR"

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
