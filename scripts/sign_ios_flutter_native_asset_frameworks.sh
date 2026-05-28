#!/usr/bin/env bash
set -euo pipefail

if [[ "${SDK_NAME:-}" != iphoneos* ]]; then
  exit 0
fi

if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "YES" ]]; then
  exit 0
fi

signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" || "$signing_identity" == "-" ]]; then
  signing_identity="${CODE_SIGN_IDENTITY:-}"
fi
if [[ -z "$signing_identity" || "$signing_identity" == "-" ]]; then
  echo "Skipping Flutter native asset framework signing: no code signing identity."
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}"
if [[ ! -d "$frameworks_dir" ]]; then
  exit 0
fi

sign_framework_if_needed() {
  local framework="$1"
  local executable_name
  executable_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$framework/Info.plist" 2>/dev/null || true)
  if [[ -z "$executable_name" || ! -f "$framework/$executable_name" ]]; then
    return 0
  fi

  local team_identifier
  team_identifier=$(/usr/bin/codesign -dv "$framework" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}' || true)
  if [[ -n "${DEVELOPMENT_TEAM:-}" && "$team_identifier" == "$DEVELOPMENT_TEAM" ]]; then
    return 0
  fi

  echo "Code signing Flutter native asset framework: $(basename "$framework")"
  /usr/bin/codesign \
    --force \
    --sign "$signing_identity" \
    --preserve-metadata=identifier,entitlements \
    --timestamp=none \
    "$framework"
}

while IFS= read -r -d "" framework; do
  sign_framework_if_needed "$framework"
done < <(/usr/bin/find "$frameworks_dir" -maxdepth 1 -type d -name "*.framework" -print0)
