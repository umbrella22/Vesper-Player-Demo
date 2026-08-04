#!/usr/bin/env bash
#
# 把 iOS 部署目标（IPHONEOS_DEPLOYMENT_TARGET，从 project.pbxproj 读取）
# 同步到 Flutter 生成的 SwiftPM manifest（FlutterGeneratedPluginSwiftPackage /
# FlutterFramework 的 .iOS(...) 平台声明）。
#   bash scripts/sync_ios_swiftpm_platforms.sh [仓库根目录]
#
# 被 Xcode scheme PreAction 在每个 Xcode 构建前调用（Runner.xcscheme），
# 也被 scripts/build_ios_no_codesign.sh 调用。
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PBXPROJ_PATH="$ROOT_DIR/ios/Runner.xcodeproj/project.pbxproj"
PACKAGES_DIR="$ROOT_DIR/ios/Flutter/ephemeral/Packages"
SWIFT_PACKAGE_MANIFESTS=(
  "$PACKAGES_DIR/FlutterGeneratedPluginSwiftPackage/Package.swift"
  "$PACKAGES_DIR/.packages/FlutterFramework/Package.swift"
)

resolve_ios_deployment_target() {
  local deployment_target
  deployment_target="$(
    grep -Eo 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+' "$PBXPROJ_PATH" \
      | head -n 1 \
      | awk '{print $3}'
  )"
  deployment_target="${deployment_target%;}"

  if [[ -z "${deployment_target:-}" ]]; then
    echo "Failed to resolve IPHONEOS_DEPLOYMENT_TARGET from $PBXPROJ_PATH" >&2
    exit 1
  fi

  printf '%s\n' "$deployment_target"
}

sync_swift_package_platform() {
  local deployment_target="$1"
  local manifest_path="$2"
  local package_name="$3"

  if [[ ! -f "$manifest_path" ]]; then
    echo "Missing generated Swift package manifest: $manifest_path" >&2
    echo "Run flutter pub get before building iOS." >&2
    exit 1
  fi

  local current_platform
  current_platform="$(
    grep -Eo '\.iOS\("[0-9.]+"\)' "$manifest_path" | head -n 1 || true
  )"

  local desired_platform=".iOS(\"$deployment_target\")"
  if [[ "$current_platform" == "$desired_platform" ]]; then
    echo "$package_name already targets iOS $deployment_target"
    return 0
  fi

  if [[ -n "$current_platform" ]]; then
    perl -0pi -e 's/\.iOS\("[0-9.]+"\)/.iOS("'"$deployment_target"'")/' "$manifest_path"
  else
    perl -0pi -e \
      's/(let package = Package\(\n[ \t]+name: "[^"]+",\n)/$1    platforms: [\n        .iOS("'"$deployment_target"'"),\n    ],\n/' \
      "$manifest_path"
  fi

  if ! grep -Fq "$desired_platform" "$manifest_path"; then
    echo "Failed to set the iOS platform declaration in $manifest_path" >&2
    exit 1
  fi

  echo "Updated $package_name to iOS $deployment_target"
}

deployment_target="$(resolve_ios_deployment_target)"
for manifest_path in "${SWIFT_PACKAGE_MANIFESTS[@]}"; do
  sync_swift_package_platform "$deployment_target" "$manifest_path" "$(basename "$(dirname "$manifest_path")")"
done
