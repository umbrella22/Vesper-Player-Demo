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
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    if /usr/bin/unzip -p "$artifact" "$entry" \
      | /usr/bin/strings \
      | LC_ALL=C grep -F "$marker" >/dev/null; then
      fail "optional diagnostics Flutter registrar is packaged in $entry"
    fi
  done < <(LC_ALL=C grep -E "$entry_pattern" "$listing" || true)
}

case "$artifact" in
  *.apk)
    /usr/bin/unzip -Z1 "$artifact" > "$listing"
    check_listing
    scan_archive_entries "$android_registrar" '(^|/)classes([0-9]+)?[.]dex$'
    ;;
  *.ipa)
    /usr/bin/unzip -Z1 "$artifact" > "$listing"
    check_listing
    scan_archive_entries "$ios_registrar" '^Payload/[^/]+[.]app/[^/]+$'
    ;;
  *.app)
    if [[ ! -d "$artifact" ]]; then
      fail "the .app input is not a directory"
    fi
    /usr/bin/find "$artifact" -print > "$listing"
    check_listing
    for candidate in "$artifact"/*; do
      [[ -f "$candidate" ]] || continue
      if /usr/bin/strings "$candidate" \
        | LC_ALL=C grep -F "$ios_registrar" >/dev/null; then
        fail "optional diagnostics Flutter registrar is packaged in $(basename "$candidate")"
      fi
    done
    ;;
  *)
    fail "unsupported artifact type"
    ;;
esac

echo "Verified Release artifact excludes the optional performance diagnostics plugin: $artifact"
