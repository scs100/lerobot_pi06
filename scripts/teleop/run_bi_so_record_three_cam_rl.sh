#!/usr/bin/env bash
# Dual-arm SO101 RL/HIL record with three OpenCV cameras to LeRobot dataset format.
# This script is intended for human-in-loop recording (intervention + success/failure labels).
#
# Usage:
#   set -a && source scripts/teleop/so101_bi_three_cam.env && set +a
#   export DATASET_REPO_ID=<HF_USERNAME_OR_ORG>/<DATASET_NAME>
#   export DATASET_SINGLE_TASK="bimanual manipulation task"
#   export DATASET_NUM_EPISODES=50
#   ./scripts/teleop/run_bi_so_record_three_cam_rl.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LERO_CMD="$(command -v lerobot-human-inloop-record 2>/dev/null || true)"
if [[ -z "$LERO_CMD" ]]; then
  for d in "$HOME/miniconda3/envs"/*/bin "$HOME/anaconda3/envs"/*/bin "$HOME/mambaforge/envs"/*/bin; do
    if [[ -x "${d}/lerobot-human-inloop-record" ]]; then
      LERO_CMD="${d}/lerobot-human-inloop-record"
      break
    fi
  done
fi
if [[ -z "$LERO_CMD" ]]; then
  echo "ERROR: lerobot-human-inloop-record not in PATH. Activate your conda env (e.g. conda activate lerobot-pi06)." >&2
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
CAM_LEFT_FPS="${CAM_LEFT_FPS:-${CAM_FPS}}"
CAM_RIGHT_FPS="${CAM_RIGHT_FPS:-${CAM_FPS}}"
CAM_FRONT_FPS="${CAM_FRONT_FPS:-${CAM_FPS}}"
CAM_FOURCC="${CAM_FOURCC:-MJPG}"
CAM_LEFT_FOURCC="${CAM_LEFT_FOURCC:-${CAM_FOURCC}}"
CAM_RIGHT_FOURCC="${CAM_RIGHT_FOURCC:-${CAM_FOURCC}}"
CAM_FRONT_FOURCC="${CAM_FRONT_FOURCC:-${CAM_FOURCC}}"
CAM_ROTATION="${CAM_ROTATION:-}"
DISPLAY_DATA="${DISPLAY_DATA:-true}"
PLAY_SOUNDS="${PLAY_SOUNDS:-false}"
DATASET_REPO_ID="${DATASET_REPO_ID:-}"
DATASET_SINGLE_TASK="${DATASET_SINGLE_TASK:-so101 dual-arm teleop task}"
DATASET_NUM_EPISODES="${DATASET_NUM_EPISODES:-20}"
DATASET_EPISODE_TIME_S="${DATASET_EPISODE_TIME_S:-86400}"
DATASET_RESET_TIME_S="${DATASET_RESET_TIME_S:-0}"
DATASET_PUSH_TO_HUB="${DATASET_PUSH_TO_HUB:-false}"
DATASET_VCODEC="${DATASET_VCODEC:-h264}"
WAIT_FOR_EPISODE_START="${WAIT_FOR_EPISODE_START:-true}"
EPISODE_START_KEY="${EPISODE_START_KEY:-pagedown}"
EPISODE_END_KEY="${EPISODE_END_KEY:-end}"
EPISODE_DISCARD_KEY="${EPISODE_DISCARD_KEY:-home}"

# Use less common defaults for RL/HIL to reduce accidental presses.
INTERVENTION_TOGGLE_KEY="${INTERVENTION_TOGGLE_KEY:-9}"
EPISODE_SUCCESS_KEY="${EPISODE_SUCCESS_KEY:-[}"
EPISODE_FAILURE_KEY="${EPISODE_FAILURE_KEY:-]}"
LEROBOT_ENABLE_ARROW_HOTKEYS="${LEROBOT_ENABLE_ARROW_HOTKEYS:-false}"
export LEROBOT_ENABLE_ARROW_HOTKEYS

if [[ -z "$CAM_FRONT" ]]; then
  echo "ERROR: CAM_FRONT is not set. Plug a third camera and export CAM_FRONT in scripts/teleop/so101_bi_three_cam.env." >&2
  exit 1
fi
if [[ -z "$DATASET_REPO_ID" ]]; then
  echo "ERROR: DATASET_REPO_ID is required. Example: export DATASET_REPO_ID=my-hf-user/so101_three_cam_round1" >&2
  exit 1
fi

_cam_rot_json() {
  if [[ -n "${CAM_ROTATION}" && "${CAM_ROTATION}" != "0" ]]; then
    printf ', rotation: %s' "${CAM_ROTATION}"
  fi
}

LEFT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_LEFT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_LEFT_FPS}$(_cam_rot_json), fourcc: \"${CAM_LEFT_FOURCC}\"}}"
RIGHT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_RIGHT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_RIGHT_FPS}$(_cam_rot_json), fourcc: \"${CAM_RIGHT_FOURCC}\"}, front: {type: opencv, index_or_path: \"${CAM_FRONT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_FRONT_FPS}$(_cam_rot_json), fourcc: \"${CAM_FRONT_FOURCC}\"}}"

echo "Mode: RL/HIL (human-in-loop). Keys: start=${EPISODE_START_KEY}, end=${EPISODE_END_KEY}, discard=${EPISODE_DISCARD_KEY}, toggle=${INTERVENTION_TOGGLE_KEY}, success=${EPISODE_SUCCESS_KEY}, failure=${EPISODE_FAILURE_KEY}" >&2

exec "$LERO_CMD" \
  --robot.type=bi_so_follower \
  --robot.left_arm_config.port="${LEFT_FOLLOWER_PORT}" \
  --robot.right_arm_config.port="${RIGHT_FOLLOWER_PORT}" \
  --robot.left_arm_config.disable_torque_on_disconnect=false \
  --robot.right_arm_config.disable_torque_on_disconnect=false \
  --robot.id="${ROBOT_ID}" \
  --robot.left_arm_config.cameras="${LEFT_CAMERAS}" \
  --robot.right_arm_config.cameras="${RIGHT_CAMERAS}" \
  --teleop.type=bi_so_leader \
  --teleop.left_arm_config.port="${LEFT_LEADER_PORT}" \
  --teleop.right_arm_config.port="${RIGHT_LEADER_PORT}" \
  --teleop.id="${TELEOP_ID}" \
  --dataset.repo_id="${DATASET_REPO_ID}" \
  --dataset.single_task="${DATASET_SINGLE_TASK}" \
  --dataset.num_episodes="${DATASET_NUM_EPISODES}" \
  --dataset.episode_time_s="${DATASET_EPISODE_TIME_S}" \
  --dataset.reset_time_s="${DATASET_RESET_TIME_S}" \
  --dataset.push_to_hub="${DATASET_PUSH_TO_HUB}" \
  --dataset.vcodec="${DATASET_VCODEC}" \
  --wait_for_episode_start="${WAIT_FOR_EPISODE_START}" \
  --episode_start_key="${EPISODE_START_KEY}" \
  --episode_end_key="${EPISODE_END_KEY}" \
  --episode_discard_key="${EPISODE_DISCARD_KEY}" \
  --play_sounds="${PLAY_SOUNDS}" \
  --intervention_toggle_key="${INTERVENTION_TOGGLE_KEY}" \
  --episode_success_key="${EPISODE_SUCCESS_KEY}" \
  --episode_failure_key="${EPISODE_FAILURE_KEY}" \
  --display_data="${DISPLAY_DATA}"
