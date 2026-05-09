#!/usr/bin/env bash
# Validate V4L devices for bi_so_follower + multiple OpenCV cameras.
# Plan step 1–3: v4l-utils install hint, enumerate by-path, optional format listing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-}"
if [[ -z "$PYTHON" || ! -x "$PYTHON" ]]; then
  for cand in "$HOME/miniconda3/envs"/*/bin/python "$HOME/anaconda3/envs"/*/bin/python "$(command -v python3)"; do
    [[ -n "$cand" && -x "$cand" ]] && PYTHON="$cand" && break
  done
fi
PYTHON="${PYTHON:-python3}"

echo "== V4L by-path (stable symlinks) =="
ls -la /dev/v4l/by-path/ 2>/dev/null || echo "(no /dev/v4l/by-path)"

echo ""
echo "== v4l2-ctl =="
if command -v v4l2-ctl >/dev/null 2>&1; then
  v4l2-ctl --version
else
  echo "v4l2-ctl not found. Install with:"
  echo "  sudo apt-get update && sudo apt-get install -y v4l-utils"
  echo "Then re-run this script with CAM_* set to probe formats."
fi

# Override these for your machine (defaults match common dual-USB + optional third cam).
CAM_LEFT="${CAM_LEFT:-/dev/v4l/by-path/pci-0000:0e:00.0-usb-0:2:1.0-video-index0}"
CAM_RIGHT="${CAM_RIGHT:-/dev/v4l/by-path/pci-0000:0e:00.0-usb-0:3:1.0-video-index0}"
CAM_FRONT="${CAM_FRONT:-}"

echo ""
echo "== Paths (env CAM_LEFT / CAM_RIGHT / CAM_FRONT) =="
echo "  CAM_LEFT=$CAM_LEFT"
echo "  CAM_RIGHT=$CAM_RIGHT"
echo "  CAM_FRONT=${CAM_FRONT:-<unset — set when third camera is plugged>}"

if command -v v4l2-ctl >/dev/null 2>&1; then
  echo ""
  for dev in "$CAM_LEFT" "$CAM_RIGHT"; do
    [[ -e "$dev" ]] || { echo "Skip missing: $dev"; continue; }
    echo "--- v4l2-ctl --list-formats-ext: $dev ---"
    v4l2-ctl -d "$dev" --list-formats-ext || true
  done
  if [[ -n "$CAM_FRONT" && -e "$CAM_FRONT" ]]; then
    echo "--- v4l2-ctl --list-formats-ext: $CAM_FRONT ---"
    v4l2-ctl -d "$CAM_FRONT" --list-formats-ext || true
  fi
fi

echo ""
echo "== OpenCV quick probe (640x480, one frame per device) =="
"$PYTHON" "$ROOT/scripts/probe_v4l_opencv.py" "$CAM_LEFT" "$CAM_RIGHT" ${CAM_FRONT:+"$CAM_FRONT"}
