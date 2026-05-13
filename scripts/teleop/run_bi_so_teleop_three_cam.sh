#!/usr/bin/env bash
# Dual-arm SO101 teleop with three OpenCV cameras (left wrist, right wrist, front on right arm config).
# Usage:
#   cp scripts/teleop/so101_bi_three_cam.env.example scripts/teleop/so101_bi_three_cam.env  # edit CAM_FRONT + PCI paths
#   source scripts/teleop/so101_bi_three_cam.env
#   ./scripts/teleop/run_bi_so_teleop_three_cam.sh
#
# Smoke test (front camera only):  FRONT_ONLY=1 ./scripts/teleop/run_bi_so_teleop_three_cam.sh
#
# Optional: CAM_ROTATION=180  (Cv2Rotation: 0, 90, 180, or 270) applies to every OpenCV camera block below.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LERO_CMD="$(command -v lerobot-teleoperate 2>/dev/null || true)"
if [[ -z "$LERO_CMD" ]]; then
  for d in "$HOME/miniconda3/envs"/*/bin "$HOME/anaconda3/envs"/*/bin "$HOME/mambaforge/envs"/*/bin; do
    if [[ -x "${d}/lerobot-teleoperate" ]]; then
      LERO_CMD="${d}/lerobot-teleoperate"
      break
    fi
  done
fi
if [[ -z "$LERO_CMD" ]]; then
  echo "ERROR: lerobot-teleoperate not in PATH. Activate your conda env (e.g. conda activate lerobot-pi06)." >&2
  exit 127
fi

CAM_LEFT="${CAM_LEFT:-/dev/v4l/by-path/pci-0000:0e:00.0-usb-0:2:1.0-video-index0}"
CAM_RIGHT="${CAM_RIGHT:-/dev/v4l/by-path/pci-0000:0e:00.0-usb-0:3:1.0-video-index0}"
CAM_FRONT="${CAM_FRONT:-}"
LEFT_FOLLOWER_PORT="${LEFT_FOLLOWER_PORT:-/dev/ttyACM3}"
RIGHT_FOLLOWER_PORT="${RIGHT_FOLLOWER_PORT:-/dev/ttyACM2}"
LEFT_LEADER_PORT="${LEFT_LEADER_PORT:-/dev/ttyACM0}"
RIGHT_LEADER_PORT="${RIGHT_LEADER_PORT:-/dev/ttyACM1}"
ROBOT_ID="${ROBOT_ID:-my_so101_follower}"
TELEOP_ID="${TELEOP_ID:-my_so101_leader}"
CAM_WIDTH="${CAM_WIDTH:-640}"
CAM_HEIGHT="${CAM_HEIGHT:-480}"
CAM_FPS="${CAM_FPS:-30}"
CAM_LEFT_FPS="${CAM_LEFT_FPS:-60}"
CAM_RIGHT_FPS="${CAM_RIGHT_FPS:-60}"
CAM_FRONT_FPS="${CAM_FRONT_FPS:-${CAM_FPS}}"
CAM_FOURCC="${CAM_FOURCC:-MJPG}"
CAM_LEFT_FOURCC="${CAM_LEFT_FOURCC:-MJPG}"
CAM_RIGHT_FOURCC="${CAM_RIGHT_FOURCC:-MJPG}"
CAM_FRONT_FOURCC="${CAM_FRONT_FOURCC:-${CAM_FOURCC}}"
# Matches lerobot Cv2Rotation (integer degrees); empty means omit field → NO_ROTATION.
CAM_ROTATION="${CAM_ROTATION:-}"
FRONT_ONLY="${FRONT_ONLY:-0}"
# Set DISPLAY_DATA=false if Rerun viewer is not installed (avoids rr.spawn failure).
DISPLAY_DATA="${DISPLAY_DATA:-true}"
# Single-camera smoke: which device to show as `front` on the right arm config.
CAM_SMOKE="${CAM_SMOKE:-$CAM_RIGHT}"

_cam_rot_json() {
  if [[ -n "${CAM_ROTATION}" && "${CAM_ROTATION}" != "0" ]]; then
    printf ', rotation: %s' "${CAM_ROTATION}"
  fi
}

if [[ "$FRONT_ONLY" == "1" ]]; then
  RIGHT_CAMERAS="{ front: {type: opencv, index_or_path: \"${CAM_SMOKE}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_FRONT_FPS}$(_cam_rot_json), fourcc: \"${CAM_FRONT_FOURCC}\"}}"
elif [[ -z "$CAM_FRONT" ]]; then
  echo "ERROR: CAM_FRONT is not set. Plug a third camera and export CAM_FRONT, or run smoke test:"
  echo "  FRONT_ONLY=1 $0"
  exit 1
else
  LEFT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_LEFT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_LEFT_FPS}$(_cam_rot_json), fourcc: \"${CAM_LEFT_FOURCC}\"}}"
  RIGHT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_RIGHT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_RIGHT_FPS}$(_cam_rot_json), fourcc: \"${CAM_RIGHT_FOURCC}\"}, front: {type: opencv, index_or_path: \"${CAM_FRONT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_FRONT_FPS}$(_cam_rot_json), fourcc: \"${CAM_FRONT_FOURCC}\"}}"
fi

ARGS=(
  "$LERO_CMD"
  --robot.type=bi_so_follower
  --robot.left_arm_config.port="${LEFT_FOLLOWER_PORT}"
  --robot.right_arm_config.port="${RIGHT_FOLLOWER_PORT}"
  --robot.left_arm_config.disable_torque_on_disconnect=false
  --robot.right_arm_config.disable_torque_on_disconnect=false
  --robot.id="${ROBOT_ID}"
  --teleop.type=bi_so_leader
  --teleop.left_arm_config.port="${LEFT_LEADER_PORT}"
  --teleop.right_arm_config.port="${RIGHT_LEADER_PORT}"
  --teleop.id="${TELEOP_ID}"
  --display_data="${DISPLAY_DATA}"
)

if [[ "$FRONT_ONLY" == "1" ]]; then
  ARGS+=(--robot.right_arm_config.cameras="${RIGHT_CAMERAS}")
else
  ARGS+=(--robot.left_arm_config.cameras="${LEFT_CAMERAS}")
  ARGS+=(--robot.right_arm_config.cameras="${RIGHT_CAMERAS}")
fi

exec "${ARGS[@]}"
