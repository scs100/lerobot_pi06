#!/usr/bin/env bash
# Dual-arm SO101 three-camera HIL-SERL recorder entrypoint.
# This script always runs policy inference + human takeover recording.
#
# Usage:
#   conda activate lerobot-pi06
#   export POLICY_PRETRAINED_PATH=/path/to/pretrained_model
#   export DATASET_REPO_ID=<HF_USERNAME_OR_ORG>/<DATASET_NAME>
#   ./scripts/hil_serl/teleop/run_bi_so_record_three_cam_hil_serl.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-${ROOT}/scripts/hil_serl/teleop/so101_bi_three_cam.env}"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}" >&2
  exit 1
fi

PRESERVE_OVERRIDE_VARS=(
  POLICY_PRETRAINED_PATH POLICY_PATH POLICY_DEVICE POLICY_COMPILE_MODEL
  POLICY_SYNC_TO_TELEOP POLICY_SYNC_PARALLEL RECORD_ON_INTERVENTION
  ACP_INFERENCE_ENABLE ACP_INFERENCE_USE_CFG ACP_INFERENCE_CFG_BETA
  CAM_LEFT CAM_RIGHT CAM_FRONT CAM_ROTATION
  LEFT_FOLLOWER_PORT RIGHT_FOLLOWER_PORT LEFT_LEADER_PORT RIGHT_LEADER_PORT
  ROBOT_ID TELEOP_ID ROBOT_USE_DEGREES TELEOP_USE_DEGREES
  ROBOT_CALIBRATION_DIR TELEOP_CALIBRATION_DIR
  CAM_WIDTH CAM_HEIGHT CAM_FPS CAM_LEFT_FPS CAM_RIGHT_FPS CAM_FRONT_FPS
  CAM_FOURCC CAM_LEFT_FOURCC CAM_RIGHT_FOURCC CAM_FRONT_FOURCC
  DISPLAY_DATA PLAY_SOUNDS
  DATASET_REPO_ID DATASET_SINGLE_TASK DATASET_NUM_EPISODES DATASET_EPISODE_TIME_S
  DATASET_RESET_TIME_S DATASET_PUSH_TO_HUB DATASET_VCODEC DATASET_VIDEO_ENCODING_BATCH_SIZE
  DATASET_RESUME DATASET_ASYNC_VIDEO_ENCODING DATASET_ASYNC_DEFER_STATS_EXPERIMENTAL
  DATASET_ASYNC_DEFER_SAVE_EPISODE_DATA_EXPERIMENTAL
  WAIT_FOR_EPISODE_START EPISODE_START_KEY HIL_EPISODE_END_KEY EPISODE_DISCARD_KEY
  INTERVENTION_TOGGLE_KEY EPISODE_SUCCESS_KEY EPISODE_FAILURE_KEY
  LEROBOT_ENABLE_ARROW_HOTKEYS LEROBOT_AUTO_USE_CALIBRATION TOKENIZERS_PARALLELISM
)

capture_override() {
  local key="$1"
  local holder="__override_${key}"
  if [[ -v "${key}" ]]; then
    printf -v "${holder}" "%s" "${!key}"
  else
    printf -v "${holder}" "%s" "__UNSET__"
  fi
}

restore_override() {
  local key="$1"
  local holder="__override_${key}"
  local val="${!holder:-__UNSET__}"
  if [[ "${val}" != "__UNSET__" ]]; then
    printf -v "${key}" "%s" "${val}"
    export "${key}"
  fi
}

for key in "${PRESERVE_OVERRIDE_VARS[@]}"; do
  capture_override "${key}"
done

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

for key in "${PRESERVE_OVERRIDE_VARS[@]}"; do
  restore_override "${key}"
done

is_true() {
  local raw="${1:-}"
  raw="${raw,,}"
  [[ "${raw}" == "1" || "${raw}" == "true" || "${raw}" == "yes" || "${raw}" == "y" || "${raw}" == "on" ]]
}

# Always load lerobot from this checkout's src/. The console scripts in PATH often point at another editable install.
PYTHON_BIN="${PYTHON:-$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)}"
if [[ -z "$PYTHON_BIN" ]]; then
  echo "ERROR: python not found. Activate conda (e.g. conda activate lerobot-pi06) or set PYTHON=/path/to/python." >&2
  exit 127
fi
export PYTHONPATH="${ROOT}/src:${PYTHONPATH:-}"
if ! "$PYTHON_BIN" -c "import lerobot.scripts.lerobot_human_inloop_record" 2>/dev/null; then
  echo "ERROR: Cannot import lerobot.scripts.lerobot_human_inloop_record with PYTHONPATH=${PYTHONPATH}" >&2
  exit 1
fi
echo "lerobot package: $($PYTHON_BIN -c 'import lerobot; print(lerobot.__file__)')" >&2

POLICY_PATH="${POLICY_PRETRAINED_PATH:-${POLICY_PATH:-}}"
POLICY_DEVICE="${POLICY_DEVICE:-cuda}"
POLICY_COMPILE_MODEL="${POLICY_COMPILE_MODEL:-false}"
POLICY_SYNC_TO_TELEOP="${POLICY_SYNC_TO_TELEOP:-true}"
POLICY_SYNC_PARALLEL="${POLICY_SYNC_PARALLEL:-true}"
RECORD_ON_INTERVENTION="${RECORD_ON_INTERVENTION:-true}"
ACP_INFERENCE_ENABLE="${ACP_INFERENCE_ENABLE:-true}"
ACP_INFERENCE_USE_CFG="${ACP_INFERENCE_USE_CFG:-true}"
ACP_INFERENCE_CFG_BETA="${ACP_INFERENCE_CFG_BETA:-1.0}"

CAM_LEFT="${CAM_LEFT:-/dev/v4l/by-path/pci-0000:0e:00.0-usb-0:2:1.0-video-index0}"
CAM_RIGHT="${CAM_RIGHT:-/dev/v4l/by-path/pci-0000:0e:00.0-usb-0:3:1.0-video-index0}"
CAM_FRONT="${CAM_FRONT:-}"
LEFT_FOLLOWER_PORT="${LEFT_FOLLOWER_PORT:-/dev/ttyACM3}"
RIGHT_FOLLOWER_PORT="${RIGHT_FOLLOWER_PORT:-/dev/ttyACM2}"
LEFT_LEADER_PORT="${LEFT_LEADER_PORT:-/dev/ttyACM0}"
RIGHT_LEADER_PORT="${RIGHT_LEADER_PORT:-/dev/ttyACM1}"
ROBOT_ID="${ROBOT_ID:-my_so101_follower}"
TELEOP_ID="${TELEOP_ID:-my_so101_leader}"
ROBOT_USE_DEGREES="${ROBOT_USE_DEGREES:-false}"
TELEOP_USE_DEGREES="${TELEOP_USE_DEGREES:-${ROBOT_USE_DEGREES}}"
ROBOT_CALIBRATION_DIR="${ROBOT_CALIBRATION_DIR:-}"
TELEOP_CALIBRATION_DIR="${TELEOP_CALIBRATION_DIR:-}"

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
DATASET_SINGLE_TASK="${DATASET_SINGLE_TASK:-so101 dual-arm hil-serl task}"
DATASET_NUM_EPISODES="${DATASET_NUM_EPISODES:-50}"
DATASET_EPISODE_TIME_S="${DATASET_EPISODE_TIME_S:-86400}"
DATASET_RESET_TIME_S="${DATASET_RESET_TIME_S:-0}"
DATASET_PUSH_TO_HUB="${DATASET_PUSH_TO_HUB:-false}"
DATASET_VCODEC="${DATASET_VCODEC:-h264}"
DATASET_VIDEO_ENCODING_BATCH_SIZE="${DATASET_VIDEO_ENCODING_BATCH_SIZE:-1}"
DATASET_RESUME="${DATASET_RESUME:-false}"
DATASET_ASYNC_VIDEO_ENCODING="${DATASET_ASYNC_VIDEO_ENCODING:-true}"
DATASET_ASYNC_DEFER_STATS_EXPERIMENTAL="${DATASET_ASYNC_DEFER_STATS_EXPERIMENTAL:-false}"
DATASET_ASYNC_DEFER_SAVE_EPISODE_DATA_EXPERIMENTAL="${DATASET_ASYNC_DEFER_SAVE_EPISODE_DATA_EXPERIMENTAL:-true}"

WAIT_FOR_EPISODE_START="${WAIT_FOR_EPISODE_START:-false}"
EPISODE_START_KEY="${EPISODE_START_KEY:-pagedown}"
HIL_EPISODE_END_KEY="${HIL_EPISODE_END_KEY:-none}"
EPISODE_DISCARD_KEY="${EPISODE_DISCARD_KEY:-home}"
INTERVENTION_TOGGLE_KEY="${INTERVENTION_TOGGLE_KEY:-pageup}"
EPISODE_SUCCESS_KEY="${EPISODE_SUCCESS_KEY:-pagedown}"
EPISODE_FAILURE_KEY="${EPISODE_FAILURE_KEY:-end}"

_normalized_end_key="${HIL_EPISODE_END_KEY,,}"
if [[ -z "${_normalized_end_key}" || "${_normalized_end_key}" == "none" || "${_normalized_end_key}" == "null" || "${_normalized_end_key}" == "off" || "${_normalized_end_key}" == "disable" || "${_normalized_end_key}" == "disabled" ]]; then
  EPISODE_END_KEY=""
else
  EPISODE_END_KEY="${HIL_EPISODE_END_KEY}"
fi

if is_true "${RECORD_ON_INTERVENTION}" && is_true "${WAIT_FOR_EPISODE_START}"; then
  echo "WARN: record_on_intervention=true is incompatible with wait_for_episode_start=true. Forcing wait_for_episode_start=false." >&2
  WAIT_FOR_EPISODE_START=false
fi
if [[ -n "${EPISODE_END_KEY}" && ( "${EPISODE_END_KEY}" == "${EPISODE_SUCCESS_KEY}" || "${EPISODE_END_KEY}" == "${EPISODE_FAILURE_KEY}" ) ]]; then
  echo "WARN: HIL episode_end_key conflicts with success/failure keys. Forcing episode_end_key=none." >&2
  EPISODE_END_KEY=""
fi

LEROBOT_ENABLE_ARROW_HOTKEYS="${LEROBOT_ENABLE_ARROW_HOTKEYS:-false}"
export LEROBOT_ENABLE_ARROW_HOTKEYS
export LEROBOT_AUTO_USE_CALIBRATION="${LEROBOT_AUTO_USE_CALIBRATION:-true}"
export TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM:-false}"

if [[ -z "$CAM_FRONT" ]]; then
  echo "ERROR: CAM_FRONT is not set in ${ENV_FILE}." >&2
  exit 1
fi
if [[ -z "$DATASET_REPO_ID" ]]; then
  echo "ERROR: DATASET_REPO_ID is required. Example: export DATASET_REPO_ID=my-hf-user/so101_three_cam_round1" >&2
  exit 1
fi
if [[ -z "$POLICY_PATH" ]]; then
  echo "ERROR: POLICY_PRETRAINED_PATH (or POLICY_PATH) is required for HIL-SERL recording." >&2
  exit 1
fi
if [[ -d "${POLICY_PATH}" && ! -f "${POLICY_PATH}/model.safetensors" ]]; then
  echo "ERROR: POLICY_PRETRAINED_PATH points to a local dir without model.safetensors: ${POLICY_PATH}" >&2
  exit 1
fi

for dev_path in \
  "${CAM_LEFT}" "${CAM_RIGHT}" "${CAM_FRONT}" \
  "${LEFT_FOLLOWER_PORT}" "${RIGHT_FOLLOWER_PORT}" "${LEFT_LEADER_PORT}" "${RIGHT_LEADER_PORT}"
do
  if [[ ! -e "${dev_path}" ]]; then
    echo "ERROR: required device path does not exist: ${dev_path}" >&2
    exit 1
  fi
done

_cam_rot_json() {
  if [[ -n "${CAM_ROTATION}" && "${CAM_ROTATION}" != "0" ]]; then
    printf ', rotation: %s' "${CAM_ROTATION}"
  fi
}

LEFT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_LEFT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_LEFT_FPS}$(_cam_rot_json), fourcc: \"${CAM_LEFT_FOURCC}\"}}"
RIGHT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_RIGHT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_RIGHT_FPS}$(_cam_rot_json), fourcc: \"${CAM_RIGHT_FOURCC}\"}, front: {type: opencv, index_or_path: \"${CAM_FRONT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_FRONT_FPS}$(_cam_rot_json), fourcc: \"${CAM_FRONT_FOURCC}\"}}"

COMMON_ARGS=(
  --robot.type=bi_so_follower
  --robot.left_arm_config.port="${LEFT_FOLLOWER_PORT}"
  --robot.right_arm_config.port="${RIGHT_FOLLOWER_PORT}"
  --robot.left_arm_config.disable_torque_on_disconnect=false
  --robot.right_arm_config.disable_torque_on_disconnect=false
  --robot.left_arm_config.use_degrees="${ROBOT_USE_DEGREES}"
  --robot.right_arm_config.use_degrees="${ROBOT_USE_DEGREES}"
  --robot.id="${ROBOT_ID}"
  --robot.left_arm_config.cameras="${LEFT_CAMERAS}"
  --robot.right_arm_config.cameras="${RIGHT_CAMERAS}"
  --teleop.type=bi_so_leader
  --teleop.left_arm_config.port="${LEFT_LEADER_PORT}"
  --teleop.right_arm_config.port="${RIGHT_LEADER_PORT}"
  --teleop.left_arm_config.use_degrees="${TELEOP_USE_DEGREES}"
  --teleop.right_arm_config.use_degrees="${TELEOP_USE_DEGREES}"
  --teleop.id="${TELEOP_ID}"
  --dataset.repo_id="${DATASET_REPO_ID}"
  --dataset.single_task="${DATASET_SINGLE_TASK}"
  --dataset.num_episodes="${DATASET_NUM_EPISODES}"
  --dataset.episode_time_s="${DATASET_EPISODE_TIME_S}"
  --dataset.reset_time_s="${DATASET_RESET_TIME_S}"
  --dataset.push_to_hub="${DATASET_PUSH_TO_HUB}"
  --dataset.vcodec="${DATASET_VCODEC}"
  --dataset.video_encoding_batch_size="${DATASET_VIDEO_ENCODING_BATCH_SIZE}"
  --resume="${DATASET_RESUME}"
  --dataset.async_video_encoding="${DATASET_ASYNC_VIDEO_ENCODING}"
  --dataset.async_defer_stats_experimental="${DATASET_ASYNC_DEFER_STATS_EXPERIMENTAL}"
  --dataset.async_defer_save_episode_data_experimental="${DATASET_ASYNC_DEFER_SAVE_EPISODE_DATA_EXPERIMENTAL}"
  --play_sounds="${PLAY_SOUNDS}"
  --display_data="${DISPLAY_DATA}"
)

if [[ -n "${ROBOT_CALIBRATION_DIR}" ]]; then
  COMMON_ARGS+=(--robot.calibration_dir="${ROBOT_CALIBRATION_DIR}")
fi
if [[ -n "${TELEOP_CALIBRATION_DIR}" ]]; then
  COMMON_ARGS+=(--teleop.calibration_dir="${TELEOP_CALIBRATION_DIR}")
fi

echo "Mode: HIL-SERL (policy inference + takeover)." >&2
echo "Joint control: follower(use_degrees=${ROBOT_USE_DEGREES}), leader(use_degrees=${TELEOP_USE_DEGREES})." >&2
echo "Policy: ${POLICY_PATH} (device=${POLICY_DEVICE}, compile=${POLICY_COMPILE_MODEL})" >&2
echo "Takeover: record_on_intervention=${RECORD_ON_INTERVENTION}, toggle=${INTERVENTION_TOGGLE_KEY}" >&2
echo "Episode keys: start=${EPISODE_START_KEY}, end=${EPISODE_END_KEY:-<disabled>}, discard=${EPISODE_DISCARD_KEY}, success=${EPISODE_SUCCESS_KEY}, failure=${EPISODE_FAILURE_KEY}" >&2
echo "ACP inference: enable=${ACP_INFERENCE_ENABLE}, use_cfg=${ACP_INFERENCE_USE_CFG}, cfg_beta=${ACP_INFERENCE_CFG_BETA}" >&2
echo "Calibration dirs: robot=${ROBOT_CALIBRATION_DIR:-<default>}, teleop=${TELEOP_CALIBRATION_DIR:-<default>}" >&2

HIL_ARGS=(
  --policy.path="${POLICY_PATH}"
  --policy.device="${POLICY_DEVICE}"
  --policy.compile_model="${POLICY_COMPILE_MODEL}"
  --policy_sync_to_teleop="${POLICY_SYNC_TO_TELEOP}"
  --policy_sync_parallel="${POLICY_SYNC_PARALLEL}"
  --record_on_intervention="${RECORD_ON_INTERVENTION}"
  --wait_for_episode_start="${WAIT_FOR_EPISODE_START}"
  --episode_start_key="${EPISODE_START_KEY}"
  --episode_discard_key="${EPISODE_DISCARD_KEY}"
  --intervention_toggle_key="${INTERVENTION_TOGGLE_KEY}"
  --episode_success_key="${EPISODE_SUCCESS_KEY}"
  --episode_failure_key="${EPISODE_FAILURE_KEY}"
  --acp_inference.enable="${ACP_INFERENCE_ENABLE}"
  --acp_inference.use_cfg="${ACP_INFERENCE_USE_CFG}"
  --acp_inference.cfg_beta="${ACP_INFERENCE_CFG_BETA}"
)
if [[ -n "${EPISODE_END_KEY}" ]]; then
  HIL_ARGS+=(--episode_end_key="${EPISODE_END_KEY}")
fi

exec "$PYTHON_BIN" -m lerobot.scripts.lerobot_human_inloop_record \
  "${COMMON_ARGS[@]}" \
  "${HIL_ARGS[@]}"
