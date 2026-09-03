#!/usr/bin/env bash
# Embed the optional SwiftPM diagnostics framework only in Debug/Profile apps.
set -euo pipefail

target_build_dir="${TARGET_BUILD_DIR:-}"
frameworks_folder_path="${FRAMEWORKS_FOLDER_PATH:-}"
configuration="${CONFIGURATION:-}"
if [[ -z "$target_build_dir" || -z "$frameworks_folder_path" ]]; then
  echo "Missing Xcode target framework output paths." >&2
  exit 1
fi

framework_name="VesperPlayerPerformanceDiagnosticsPlugin.framework"
destination_root="$target_build_dir/$frameworks_folder_path"
destination="$destination_root/$framework_name"
case "$destination" in
  "$target_build_dir"/*) ;;
  *)
    echo "Diagnostics framework destination escaped TARGET_BUILD_DIR." >&2
    exit 1
    ;;
esac

remove_destination() {
  if [[ -e "$destination" ]]; then
    /usr/bin/find "$destination" -depth -delete
  fi
}

if [[ "$configuration" != "Debug" && "$configuration" != "Profile" ]]; then
  remove_destination
  echo "Performance diagnostics is excluded from $configuration."
  exit 0
fi

source_framework="$target_build_dir/PackageFrameworks/$framework_name"
if [[ ! -d "$source_framework" ]]; then
  source_framework="$target_build_dir/$framework_name"
fi
if [[ ! -d "$source_framework" ]]; then
  echo "Missing SwiftPM performance diagnostics framework for $configuration." >&2
  exit 1
fi

remove_destination
/bin/mkdir -p "$destination_root"
/usr/bin/ditto "$source_framework" "$destination"

executable_name="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$destination/Info.plist"
)"
if [[ -z "$executable_name" || ! -f "$destination/$executable_name" ]]; then
  echo "Embedded diagnostics framework has no executable." >&2
  exit 1
fi

echo "Embedded optional performance diagnostics framework for $configuration."
