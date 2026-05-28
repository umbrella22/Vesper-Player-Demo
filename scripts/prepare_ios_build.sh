#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT_DIR/scripts/prepare_flutter_workspace.sh"
bash "$ROOT_DIR/scripts/sync_ios_swiftpm_platforms.sh" "$ROOT_DIR"
