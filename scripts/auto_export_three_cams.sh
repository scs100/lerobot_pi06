#!/usr/bin/env bash
# Auto-print export lines for CAM_LEFT, CAM_RIGHT, CAM_FRONT from all *video-index0* under by-path.
# Order is lexical sort of full path (adjust mapping if needed).
set -euo pipefail

mapfile -t cams < <(find /dev/v4l/by-path -maxdepth 1 -name '*video-index0' -type l 2>/dev/null | sort)

n="${#cams[@]}"
if [[ "$n" -lt 3 ]]; then
  echo "Found $n video-index0 device(s); need 3 for tri-camera teleop." >&2
  echo "Run ./scripts/v4l_snapshot.sh before.txt , plug camera, ./scripts/v4l_snapshot.sh after.txt , diff them." >&2
  printf '%s\n' "${cams[@]:-}"
  exit 1
fi

echo "# Copy-paste or: eval \"\$(./scripts/auto_export_three_cams.sh | grep '^export')\""
echo "export CAM_LEFT=${cams[0]}"
echo "export CAM_RIGHT=${cams[1]}"
echo "export CAM_FRONT=${cams[2]}"
