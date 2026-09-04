#!/usr/bin/env bash
# Verify that a Release APK, IPA, or .app does not package the optional
# performance diagnostics binary, registry fragment, or Flutter registrar.
set -euo pipefail

artifact="${1:-}"
if [[ -z "$artifact" || ! -e "$artifact" ]]; then
  echo "Usage: $0 <release.apk|release.ipa|Runner.app>" >&2
  exit 2
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/vesper-diagnostics-audit.XXXXXX")"
trap '/usr/bin/find "$temporary_dir" -depth -delete' EXIT
listing="$temporary_dir/archive-listing.txt"

forbidden_path_pattern='(^|/)(libvesper_performance_diagnostics[.]so|VesperPlayerPerformanceDiagnosticsPlugin[.]framework(/|$))|(^|/)assets/vesper/plugins/[^/]+/io[.]github[.]umbrella22[.]vesper[.]performance-diagnostics[.]json$'
android_registrar='io/github/umbrella22/vesper/player/flutter/performance_diagnostics/VesperPlayerPerformanceDiagnosticsPlugin'
ios_registrar='vesper_player_performance_diagnostics'
host_share_channel='dev.ikaros.vesper_player/performance_diagnostics_share'
host_ui_marker='open-performance-diagnostics'

fail() {
  echo "Release diagnostics exclusion failed: $1" >&2
  exit 1
}

check_listing() {
  if LC_ALL=C grep -E "$forbidden_path_pattern" "$listing" >/dev/null; then
    LC_ALL=C grep -E "$forbidden_path_pattern" "$listing" >&2
    fail "optional diagnostics payload is packaged"
  fi
}

scan_archive_entries() {
  local marker="$1"
  local entry_pattern="$2"
  local description="$3"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    if /usr/bin/unzip -p "$artifact" "$entry" \
      | /usr/bin/strings \
      | LC_ALL=C grep -F "$marker" >/dev/null; then
      fail "$description is packaged in $entry"
    fi
  done < <(LC_ALL=C grep -E "$entry_pattern" "$listing" || true)
}

scan_file() {
  local marker="$1"
  local candidate="$2"
  local description="$3"
  [[ -f "$candidate" ]] || return 0
  if /usr/bin/strings "$candidate" | LC_ALL=C grep -F "$marker" >/dev/null; then
    fail "$description is packaged in $candidate"
  fi
}

case "$artifact" in
  *.apk)
    /usr/bin/unzip -Z1 "$artifact" > "$listing"
    check_listing
    scan_archive_entries "$android_registrar" '(^|/)classes([0-9]+)?[.]dex$' \
      "optional diagnostics Flutter registrar"
    scan_archive_entries "$host_share_channel" '(^|/)classes([0-9]+)?[.]dex$' \
      "diagnostics host share channel"
    scan_archive_entries "$host_ui_marker" '(^|/)lib/[^/]+/libapp[.]so$' \
      "diagnostics host UI"
    ;;
  *.ipa)
    /usr/bin/unzip -Z1 "$artifact" > "$listing"
    check_listing
    scan_archive_entries "$ios_registrar" '^Payload/[^/]+[.]app/[^/]+$' \
      "optional diagnostics Flutter registrar"
    scan_archive_entries "$host_share_channel" '^Payload/[^/]+[.]app/[^/]+$' \
      "diagnostics host share channel"
    scan_archive_entries "$host_ui_marker" \
      '^Payload/[^/]+[.]app/Frameworks/App[.]framework/App$' \
      "diagnostics host UI"
    ;;
  *.app)
    if [[ ! -d "$artifact" ]]; then
      fail "the .app input is not a directory"
    fi
    /usr/bin/find "$artifact" -print > "$listing"
    check_listing
    for candidate in "$artifact"/*; do
      [[ -f "$candidate" ]] || continue
      scan_file "$ios_registrar" "$candidate" \
        "optional diagnostics Flutter registrar"
      scan_file "$host_share_channel" "$candidate" \
        "diagnostics host share channel"
    done
    scan_file "$host_ui_marker" "$artifact/Frameworks/App.framework/App" \
      "diagnostics host UI"
    ;;
  *)
    fail "unsupported artifact type"
    ;;
esac

echo "Verified Release artifact excludes the optional performance diagnostics plugin: $artifact"
