#!/usr/bin/env bash
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
