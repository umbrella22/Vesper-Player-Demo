#!/usr/bin/env bash
#
# 准备 Flutter 工作区：归档 stale 的 Swift package 链接目录，然后 flutter pub get。
# 干净的 pub get 会重建 ios/Flutter/ephemeral/Packages 下的链接，避免旧链接
# 指向不存在的包导致 iOS 构建失败。
#   bash scripts/prepare_flutter_workspace.sh
#
# 被 scripts/build_ios_no_codesign.sh、Android CI
# （.github/workflows/android-release-apk.yml）以及本机初始化调用。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_DIR="$ROOT_DIR/ios/Flutter/ephemeral/Packages"
SWIFT_PACKAGE_LINK_DIR="$PACKAGES_DIR/.packages"

if [[ -d "$SWIFT_PACKAGE_LINK_DIR" ]]; then
  archived_path="${SWIFT_PACKAGE_LINK_DIR}.stale.$(date +%Y%m%d%H%M%S)"
  mv "$SWIFT_PACKAGE_LINK_DIR" "$archived_path"
  echo "Archived stale Swift package links:"
  echo "  $archived_path"
fi

flutter pub get
