#!/usr/bin/env bash
# Save /dev/v4l/by-path listing for before/after plugging a camera; compare with diff.
# Usage:
#   ./scripts/v4l_snapshot.sh before.txt
#   # plug third camera
#   ./scripts/v4l_snapshot.sh after.txt
#   diff -u before.txt after.txt
set -euo pipefail

OUT="${1:?usage: $0 <output.txt>}"
{
  echo "# $(date -Iseconds)"
  echo "## ls -la /dev/v4l/by-path"
  ls -la /dev/v4l/by-path/ 2>/dev/null || true
  echo ""
  echo "## video-index0 symlinks (sorted)"
  find /dev/v4l/by-path -maxdepth 1 -name '*video-index0' -type l 2>/dev/null | sort || true
} >"$OUT"
echo "Wrote $OUT"
