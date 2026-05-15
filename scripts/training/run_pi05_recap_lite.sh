#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/training/run_pi05_recap_lite.sh <command> [options]

Commands:
  collect       4090: 采集 RECAP 数据（策略推理 + 干预 + 成功/失败标签）
  sync-up       4090: rsync 采集数据到 A100
  value-train   A100: 8 卡训练 value
  value-infer   A100: value 推理并写回 value/advantage/indicator
  acp-train     A100: 8 卡 ACP 训练
  sync-down     4090: rsync 拉回 ACP checkpoint
  eval          4090: ACP 推理评测并输出 dataset report

Core options:
  --run-id ID
  --task-name NAME
  --recap-repo-id ID
  --eval-repo-id ID

Path options:
  --local-project-root PATH
  --cloud-project-root PATH
  --dataset-root-local PATH
  --dataset-root-cloud PATH
  --base-policy-path-local PATH
  --base-policy-path-cloud PATH
  --value-out-cloud-root PATH
  --acp-out-cloud-root PATH
  --acp-out-local-root PATH

Rsync options:
  --cloud-ssh USER@HOST
  --cloud-rsync-ssh-opts "SSH_OPTS"
  --allow-existing-dst true|false   (default: false)

Collect/eval options:
  --camera-env PATH
  --dataset-single-task TEXT
  --dataset-num-episodes N
  --dataset-num-episodes-eval N
  --dataset-episode-time-s N
  --dataset-reset-time-s N
  --dataset-vcodec CODEC
  --display-data true|false
  --play-sounds true|false
  --intervention-toggle-key KEY
  --episode-start-key KEY
  --episode-end-key KEY
  --episode-discard-key KEY
  --episode-success-key KEY
  --episode-failure-key KEY
  --acp-cfg-beta F

Value/ACP training options:
  --cloud-num-processes N
  --cloud-mixed-precision MODE
  --cloud-cuda-visible-devices IDS
  --value-steps N
  --value-batch-size N
  --value-num-workers N
  --value-save-freq N
  --value-log-freq N
  --value-c-fail-coef F
  --infer-batch-size N
  --infer-num-workers N
  --acp-n-step N
  --acp-positive-ratio F
  --acp-force-intervention-positive true|false
  --acp-c-fail-coef F
  --acp-steps N
  --acp-batch-size N
  --acp-save-freq N
  --acp-log-freq N
  --acp-indicator-dropout-prob F

Examples:
  # 4090 采集
  bash scripts/training/run_pi05_recap_lite.sh collect \
    --run-id "$(date +%F_%H-%M-%S)" \
    --base-policy-path-local /path/to/pi05_ft/checkpoints/005000/pretrained_model \
    --camera-env scripts/teleop/so101_bi_three_cam.env

  # 4090 同步到 A100
  bash scripts/training/run_pi05_recap_lite.sh sync-up \
    --run-id 2026-05-13_17-00-00 \
    --cloud-ssh user@a100-host \
    --dataset-root-local /media/jushen/stone-shi/lerobot_v30 \
    --dataset-root-cloud /data/lerobot_v30

  # A100 8 卡 value 训练
  bash scripts/training/run_pi05_recap_lite.sh value-train \
    --run-id 2026-05-13_17-00-00 \
    --dataset-root-cloud /data/lerobot_v30 \
    --cloud-num-processes 8 \
    --cloud-cuda-visible-devices 0,1,2,3,4,5,6,7
EOF
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_err() {
  printf '[ERR] %s\n' "$*" >&2
}

normalize_bool() {
  local var_name="$1"
  local raw="${!var_name:-}"
  raw="${raw,,}"
  case "${raw}" in
    true|false) ;;
    *)
      log_err "Invalid boolean for ${var_name}: '${raw}' (expect true/false)"
      exit 2
      ;;
  esac
  printf -v "${var_name}" '%s' "${raw}"
}

ensure_dir_exists() {
  local path="$1"
  local label="$2"
  if [[ ! -d "${path}" ]]; then
    log_err "${label} not found: ${path}"
    exit 1
  fi
}

ensure_file_exists() {
  local path="$1"
  local label="$2"
  if [[ ! -f "${path}" ]]; then
    log_err "${label} not found: ${path}"
    exit 1
  fi
}

ensure_path_absent() {
  local path="$1"
  local label="$2"
  local allow_existing="$3"
  if [[ -e "${path}" ]]; then
    if [[ "${allow_existing}" == "true" ]]; then
      log_warn "${label} already exists, continue because allow-existing-dst=true: ${path}"
      return 0
    fi
    log_err "${label} already exists, abort to avoid overwrite: ${path}"
    exit 1
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_err "Command not found: ${cmd}"
    exit 1
  fi
}

require_env_value() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    log_err "Required env var is missing: ${var_name}"
    exit 1
  fi
}

resolve_repo_dir() {
  local root="$1"
  local repo_id="$2"
  printf '%s/%s\n' "${root%/}" "${repo_id}"
}

build_ssh_base() {
  SSH_BASE=(ssh)
  if [[ -n "${CLOUD_RSYNC_SSH_OPTS}" ]]; then
    read -r -a ssh_opts <<< "${CLOUD_RSYNC_SSH_OPTS}"
    SSH_BASE+=("${ssh_opts[@]}")
  fi
}

remote_path_exists() {
  local remote_path="$1"
  local quoted
  quoted="$(printf '%q' "${remote_path}")"
  build_ssh_base
  "${SSH_BASE[@]}" "${CLOUD_SSH}" "test -e ${quoted}"
}

remote_mkdir_p() {
  local remote_path="$1"
  local quoted
  quoted="$(printf '%q' "${remote_path}")"
  build_ssh_base
  "${SSH_BASE[@]}" "${CLOUD_SSH}" "mkdir -p ${quoted}"
}

rsync_ssh_cmd() {
  if [[ -n "${CLOUD_RSYNC_SSH_OPTS}" ]]; then
    printf 'ssh %s' "${CLOUD_RSYNC_SSH_OPTS}"
    return 0
  fi
  printf 'ssh'
}

load_camera_env() {
  local env_path="$1"
  if [[ "${env_path}" != /* ]]; then
    if [[ -f "${LOCAL_PROJECT_ROOT}/${env_path}" ]]; then
      env_path="${LOCAL_PROJECT_ROOT}/${env_path}"
    fi
  fi
  ensure_file_exists "${env_path}" "camera env"
  set -a
  # shellcheck disable=SC1090
  source "${env_path}"
  set +a
}

build_camera_configs() {
  CAM_WIDTH="${CAM_WIDTH:-640}"
  CAM_HEIGHT="${CAM_HEIGHT:-480}"
  CAM_ROTATION="${CAM_ROTATION:-0}"
  CAM_LEFT_FPS="${CAM_LEFT_FPS:-30}"
  CAM_RIGHT_FPS="${CAM_RIGHT_FPS:-30}"
  CAM_FRONT_FPS="${CAM_FRONT_FPS:-30}"
  CAM_LEFT_FOURCC="${CAM_LEFT_FOURCC:-MJPG}"
  CAM_RIGHT_FOURCC="${CAM_RIGHT_FOURCC:-MJPG}"
  CAM_FRONT_FOURCC="${CAM_FRONT_FOURCC:-MJPG}"

  if [[ -z "${CAM_LEFT:-}" || -z "${CAM_RIGHT:-}" || -z "${CAM_FRONT:-}" ]]; then
    log_err "CAM_LEFT/CAM_RIGHT/CAM_FRONT missing in camera env."
    exit 1
  fi

  LEFT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_LEFT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_LEFT_FPS}, rotation: ${CAM_ROTATION}, fourcc: \"${CAM_LEFT_FOURCC}\"}}"
  RIGHT_CAMERAS="{ wrist: {type: opencv, index_or_path: \"${CAM_RIGHT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_RIGHT_FPS}, rotation: ${CAM_ROTATION}, fourcc: \"${CAM_RIGHT_FOURCC}\"}, front: {type: opencv, index_or_path: \"${CAM_FRONT}\", width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_FRONT_FPS}, rotation: ${CAM_ROTATION}, fourcc: \"${CAM_FRONT_FOURCC}\"}}"
}

run_collect() {
  require_command lerobot-human-inloop-record
  ensure_dir_exists "${LOCAL_PROJECT_ROOT}" "local project root"
  ensure_dir_exists "${DATASET_ROOT_LOCAL}" "dataset root local"
  ensure_file_exists "${BASE_POLICY_PATH_LOCAL}/config.json" "base policy config (local)"
  ensure_file_exists "${BASE_POLICY_PATH_LOCAL}/model.safetensors" "base policy weight (local)"
  ensure_path_absent "${RECAP_DATASET_DIR_LOCAL}" "local recap dataset dir" "${ALLOW_EXISTING_DST}"

  cd "${LOCAL_PROJECT_ROOT}"
  load_camera_env "${CAMERA_ENV}"
  build_camera_configs
  require_env_value LEFT_FOLLOWER_PORT
  require_env_value RIGHT_FOLLOWER_PORT
  require_env_value LEFT_LEADER_PORT
  require_env_value RIGHT_LEADER_PORT

  log_info "collect run_id=${RUN_ID}"
  log_info "dataset=${RECAP_REPO_ID} root=${DATASET_ROOT_LOCAL}"
  log_info "base_policy_path_local=${BASE_POLICY_PATH_LOCAL}"

  lerobot-human-inloop-record \
    --robot.type=bi_so_follower \
    --robot.id="${ROBOT_ID:-my_so101_follower}" \
    --robot.left_arm_config.port="${LEFT_FOLLOWER_PORT}" \
    --robot.right_arm_config.port="${RIGHT_FOLLOWER_PORT}" \
    --robot.left_arm_config.disable_torque_on_disconnect=false \
    --robot.right_arm_config.disable_torque_on_disconnect=false \
    --robot.left_arm_config.cameras="${LEFT_CAMERAS}" \
    --robot.right_arm_config.cameras="${RIGHT_CAMERAS}" \
    --teleop.type=bi_so_leader \
    --teleop.id="${TELEOP_ID:-my_so101_leader}" \
    --teleop.left_arm_config.port="${LEFT_LEADER_PORT}" \
    --teleop.right_arm_config.port="${RIGHT_LEADER_PORT}" \
    --policy.path="${BASE_POLICY_PATH_LOCAL}" \
    --policy.device=cuda \
    --dataset.repo_id="${RECAP_REPO_ID}" \
    --dataset.root="${DATASET_ROOT_LOCAL}" \
    --dataset.single_task="${DATASET_SINGLE_TASK}" \
    --dataset.num_episodes="${DATASET_NUM_EPISODES}" \
    --dataset.episode_time_s="${DATASET_EPISODE_TIME_S}" \
    --dataset.reset_time_s="${DATASET_RESET_TIME_S}" \
    --dataset.push_to_hub=false \
    --dataset.vcodec="${DATASET_VCODEC}" \
    --wait_for_episode_start=true \
    --episode_start_key="${EPISODE_START_KEY}" \
    --episode_end_key="${EPISODE_END_KEY}" \
    --episode_discard_key="${EPISODE_DISCARD_KEY}" \
    --intervention_toggle_key="${INTERVENTION_TOGGLE_KEY}" \
    --episode_success_key="${EPISODE_SUCCESS_KEY}" \
    --episode_failure_key="${EPISODE_FAILURE_KEY}" \
    --play_sounds="${PLAY_SOUNDS}" \
    --display_data="${DISPLAY_DATA}"
}

run_sync_up() {
  require_command rsync
  require_command ssh
  if [[ -z "${CLOUD_SSH}" ]]; then
    log_err "--cloud-ssh is required for sync-up."
    exit 2
  fi

  ensure_dir_exists "${DATASET_ROOT_LOCAL}" "dataset root local"
  ensure_dir_exists "$(dirname "${RECAP_DATASET_DIR_LOCAL}")" "local recap dataset parent"
  ensure_dir_exists "${RECAP_DATASET_DIR_LOCAL}" "local recap dataset dir"

  if remote_path_exists "${RECAP_DATASET_DIR_CLOUD}"; then
    if [[ "${ALLOW_EXISTING_DST}" != "true" ]]; then
      log_err "remote dataset dir exists, abort to avoid overwrite: ${RECAP_DATASET_DIR_CLOUD}"
      exit 1
    fi
    log_warn "remote dataset dir exists, continue because allow-existing-dst=true: ${RECAP_DATASET_DIR_CLOUD}"
  fi

  remote_mkdir_p "$(dirname "${RECAP_DATASET_DIR_CLOUD}")"
  local rsync_ssh
  rsync_ssh="$(rsync_ssh_cmd)"
  rsync -a --info=progress2 --human-readable -e "${rsync_ssh}" \
    "${RECAP_DATASET_DIR_LOCAL}/" "${CLOUD_SSH}:${RECAP_DATASET_DIR_CLOUD}/"

  log_info "sync-up done: ${RECAP_DATASET_DIR_LOCAL} -> ${CLOUD_SSH}:${RECAP_DATASET_DIR_CLOUD}"
}

run_value_train() {
  require_command accelerate
  require_command lerobot-value-train
  ensure_dir_exists "${CLOUD_PROJECT_ROOT}" "cloud project root"
  ensure_dir_exists "${DATASET_ROOT_CLOUD}" "dataset root cloud"
  ensure_dir_exists "${RECAP_DATASET_DIR_CLOUD}" "cloud recap dataset dir"
  ensure_path_absent "${VALUE_OUT_CLOUD}" "value output dir (cloud)" "${ALLOW_EXISTING_DST}"
  mkdir -p "${VALUE_OUT_CLOUD_ROOT}"

  cd "${CLOUD_PROJECT_ROOT}"
  log_info "value-train run_id=${RUN_ID}"
  log_info "dataset=${RECAP_REPO_ID} root=${DATASET_ROOT_CLOUD}"
  log_info "output=${VALUE_OUT_CLOUD}"

  local -a cmd
  cmd=(
    accelerate launch
    --num_processes="${CLOUD_NUM_PROCESSES}"
    --mixed_precision="${CLOUD_MIXED_PRECISION}"
    lerobot-value-train
    "--dataset.repo_id=${RECAP_REPO_ID}"
    "--dataset.root=${DATASET_ROOT_CLOUD}"
    "--value.type=pistar06"
    "--value.device=cuda"
    "--value.dtype=bfloat16"
    "--targets.success_field=episode_success"
    "--targets.default_success=failure"
    "--targets.c_fail_coef=${VALUE_C_FAIL_COEF}"
    "--steps=${VALUE_STEPS}"
    "--batch_size=${VALUE_BATCH_SIZE}"
    "--num_workers=${VALUE_NUM_WORKERS}"
    "--save_freq=${VALUE_SAVE_FREQ}"
    "--log_freq=${VALUE_LOG_FREQ}"
    "--output_dir=${VALUE_OUT_CLOUD}"
    "--wandb.enable=false"
  )

  if [[ -n "${CLOUD_CUDA_VISIBLE_DEVICES}" ]]; then
    CUDA_VISIBLE_DEVICES="${CLOUD_CUDA_VISIBLE_DEVICES}" "${cmd[@]}"
    return 0
  fi
  "${cmd[@]}"
}

run_value_infer() {
  require_command lerobot-value-infer
  ensure_dir_exists "${CLOUD_PROJECT_ROOT}" "cloud project root"
  ensure_dir_exists "${DATASET_ROOT_CLOUD}" "dataset root cloud"
  ensure_dir_exists "${RECAP_DATASET_DIR_CLOUD}" "cloud recap dataset dir"
  ensure_dir_exists "${VALUE_OUT_CLOUD}" "value output dir (cloud)"

  cd "${CLOUD_PROJECT_ROOT}"
  log_info "value-infer run_id=${RUN_ID}"
  log_info "dataset=${RECAP_REPO_ID} root=${DATASET_ROOT_CLOUD}"
  log_info "checkpoint_path=${VALUE_OUT_CLOUD}"

  lerobot-value-infer \
    --dataset.repo_id="${RECAP_REPO_ID}" \
    --dataset.root="${DATASET_ROOT_CLOUD}" \
    --dataset.success_field=episode_success \
    --dataset.default_success=failure \
    --inference.checkpoint_path="${VALUE_OUT_CLOUD}" \
    --inference.checkpoint_ref=last \
    --runtime.device=cuda \
    --runtime.batch_size="${INFER_BATCH_SIZE}" \
    --runtime.num_workers="${INFER_NUM_WORKERS}" \
    --acp.enable=true \
    --acp.n_step="${ACP_N_STEP}" \
    --acp.positive_ratio="${ACP_POSITIVE_RATIO}" \
    --acp.force_intervention_positive="${ACP_FORCE_INTERVENTION_POSITIVE}" \
    --acp.intervention_field=complementary_info.is_intervention \
    --acp.value_field=complementary_info.value \
    --acp.advantage_field=complementary_info.advantage \
    --acp.indicator_field=complementary_info.acp_indicator \
    --acp.c_fail_coef="${ACP_C_FAIL_COEF}" \
    --viz.enable=false
}

run_acp_train() {
  require_command accelerate
  require_command lerobot-train
  ensure_dir_exists "${CLOUD_PROJECT_ROOT}" "cloud project root"
  ensure_dir_exists "${DATASET_ROOT_CLOUD}" "dataset root cloud"
  ensure_dir_exists "${RECAP_DATASET_DIR_CLOUD}" "cloud recap dataset dir"
  ensure_file_exists "${BASE_POLICY_PATH_CLOUD}/config.json" "base policy config (cloud)"
  ensure_file_exists "${BASE_POLICY_PATH_CLOUD}/model.safetensors" "base policy weight (cloud)"
  ensure_path_absent "${ACP_OUT_CLOUD}" "acp output dir (cloud)" "${ALLOW_EXISTING_DST}"
  mkdir -p "${ACP_OUT_CLOUD_ROOT}"

  cd "${CLOUD_PROJECT_ROOT}"
  log_info "acp-train run_id=${RUN_ID}"
  log_info "dataset=${RECAP_REPO_ID} root=${DATASET_ROOT_CLOUD}"
  log_info "base_policy_path_cloud=${BASE_POLICY_PATH_CLOUD}"
  log_info "output=${ACP_OUT_CLOUD}"

  local -a cmd
  cmd=(
    accelerate launch
    --num_processes="${CLOUD_NUM_PROCESSES}"
    --mixed_precision="${CLOUD_MIXED_PRECISION}"
    lerobot-train
    "--dataset.repo_id=${RECAP_REPO_ID}"
    "--dataset.root=${DATASET_ROOT_CLOUD}"
    "--policy.path=${BASE_POLICY_PATH_CLOUD}"
    "--policy.device=cuda"
    "--batch_size=${ACP_BATCH_SIZE}"
    "--steps=${ACP_STEPS}"
    "--save_freq=${ACP_SAVE_FREQ}"
    "--log_freq=${ACP_LOG_FREQ}"
    "--acp.enable=true"
    "--acp.indicator_field=complementary_info.acp_indicator"
    "--acp.indicator_dropout_prob=${ACP_INDICATOR_DROPOUT_PROB}"
    "--output_dir=${ACP_OUT_CLOUD}"
    "--wandb.enable=false"
  )

  if [[ -n "${CLOUD_CUDA_VISIBLE_DEVICES}" ]]; then
    CUDA_VISIBLE_DEVICES="${CLOUD_CUDA_VISIBLE_DEVICES}" "${cmd[@]}"
    return 0
  fi
  "${cmd[@]}"
}

run_sync_down() {
  require_command rsync
  require_command ssh
  if [[ -z "${CLOUD_SSH}" ]]; then
    log_err "--cloud-ssh is required for sync-down."
    exit 2
  fi

  mkdir -p "${ACP_OUT_LOCAL_ROOT}"
  if ! remote_path_exists "${ACP_OUT_CLOUD}"; then
    log_err "remote acp output dir not found: ${CLOUD_SSH}:${ACP_OUT_CLOUD}"
    exit 1
  fi
  ensure_path_absent "${ACP_OUT_LOCAL}" "local acp output dir" "${ALLOW_EXISTING_DST}"

  mkdir -p "$(dirname "${ACP_OUT_LOCAL}")"
  local rsync_ssh
  rsync_ssh="$(rsync_ssh_cmd)"
  rsync -a --info=progress2 --human-readable -e "${rsync_ssh}" \
    "${CLOUD_SSH}:${ACP_OUT_CLOUD}/" "${ACP_OUT_LOCAL}/"

  log_info "sync-down done: ${CLOUD_SSH}:${ACP_OUT_CLOUD} -> ${ACP_OUT_LOCAL}"
}

run_eval() {
  require_command lerobot-human-inloop-record
  require_command lerobot-dataset-report
  ensure_dir_exists "${LOCAL_PROJECT_ROOT}" "local project root"
  ensure_dir_exists "${DATASET_ROOT_LOCAL}" "dataset root local"
  ensure_dir_exists "${ACP_OUT_LOCAL}" "local acp output dir"
  ensure_file_exists "${ACP_POLICY_PATH_LOCAL}/config.json" "acp policy config (local)"
  ensure_file_exists "${ACP_POLICY_PATH_LOCAL}/model.safetensors" "acp policy weight (local)"
  ensure_path_absent "${EVAL_DATASET_DIR_LOCAL}" "local eval dataset dir" "${ALLOW_EXISTING_DST}"

  cd "${LOCAL_PROJECT_ROOT}"
  load_camera_env "${CAMERA_ENV}"
  build_camera_configs
  require_env_value LEFT_FOLLOWER_PORT
  require_env_value RIGHT_FOLLOWER_PORT
  require_env_value LEFT_LEADER_PORT
  require_env_value RIGHT_LEADER_PORT

  log_info "eval run_id=${RUN_ID}"
  log_info "eval dataset=${EVAL_REPO_ID} root=${DATASET_ROOT_LOCAL}"
  log_info "acp_policy_path_local=${ACP_POLICY_PATH_LOCAL}"

  lerobot-human-inloop-record \
    --robot.type=bi_so_follower \
    --robot.id="${ROBOT_ID:-my_so101_follower}" \
    --robot.left_arm_config.port="${LEFT_FOLLOWER_PORT}" \
    --robot.right_arm_config.port="${RIGHT_FOLLOWER_PORT}" \
    --robot.left_arm_config.disable_torque_on_disconnect=false \
    --robot.right_arm_config.disable_torque_on_disconnect=false \
    --robot.left_arm_config.cameras="${LEFT_CAMERAS}" \
    --robot.right_arm_config.cameras="${RIGHT_CAMERAS}" \
    --teleop.type=bi_so_leader \
    --teleop.id="${TELEOP_ID:-my_so101_leader}" \
    --teleop.left_arm_config.port="${LEFT_LEADER_PORT}" \
    --teleop.right_arm_config.port="${RIGHT_LEADER_PORT}" \
    --policy.path="${ACP_POLICY_PATH_LOCAL}" \
    --policy.device=cuda \
    --acp_inference.enable=true \
    --acp_inference.use_cfg=true \
    --acp_inference.cfg_beta="${ACP_CFG_BETA}" \
    --intervention_state_machine_enabled=false \
    --dataset.repo_id="${EVAL_REPO_ID}" \
    --dataset.root="${DATASET_ROOT_LOCAL}" \
    --dataset.single_task="${DATASET_SINGLE_TASK}" \
    --dataset.num_episodes="${DATASET_NUM_EPISODES_EVAL}" \
    --dataset.episode_time_s="${DATASET_EPISODE_TIME_S}" \
    --dataset.reset_time_s="${DATASET_RESET_TIME_S}" \
    --dataset.push_to_hub=false \
    --dataset.vcodec="${DATASET_VCODEC}" \
    --wait_for_episode_start=true \
    --episode_start_key="${EPISODE_START_KEY}" \
    --episode_end_key="${EPISODE_END_KEY}" \
    --episode_discard_key="${EPISODE_DISCARD_KEY}" \
    --episode_success_key="${EPISODE_SUCCESS_KEY}" \
    --episode_failure_key="${EPISODE_FAILURE_KEY}" \
    --play_sounds="${PLAY_SOUNDS}" \
    --display_data="${DISPLAY_DATA}"

  lerobot-dataset-report --dataset "${EVAL_REPO_ID}" --root "${DATASET_ROOT_LOCAL}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DEFAULT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ACTION="${1:-}"
if [[ -z "${ACTION}" || "${ACTION}" == "-h" || "${ACTION}" == "--help" || "${ACTION}" == "help" ]]; then
  usage
  exit 0
fi
shift || true

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

RUN_ID=""
TASK_NAME="so101_recap_lite"
RECAP_REPO_ID=""
EVAL_REPO_ID=""

LOCAL_PROJECT_ROOT="${PROJECT_ROOT_DEFAULT}"
CLOUD_PROJECT_ROOT="${PROJECT_ROOT_DEFAULT}"
DATASET_ROOT_LOCAL="/media/jushen/stone-shi/lerobot_v30"
DATASET_ROOT_CLOUD="/path/to/lerobot_v30"

BASE_POLICY_PATH_LOCAL=""
BASE_POLICY_PATH_CLOUD=""

VALUE_OUT_CLOUD_ROOT="/path/to/checkpoints/value"
ACP_OUT_CLOUD_ROOT="/path/to/checkpoints/acp"
ACP_OUT_LOCAL_ROOT="${PROJECT_ROOT_DEFAULT}/checkpoints/acp"

CLOUD_SSH=""
CLOUD_RSYNC_SSH_OPTS=""
ALLOW_EXISTING_DST="false"

CAMERA_ENV="scripts/teleop/so101_bi_three_cam.env"
DATASET_SINGLE_TASK="bimanual manipulation task"
DATASET_NUM_EPISODES="80"
DATASET_NUM_EPISODES_EVAL="20"
DATASET_EPISODE_TIME_S="30"
DATASET_RESET_TIME_S="10"
DATASET_VCODEC="h264"
DISPLAY_DATA="true"
PLAY_SOUNDS="false"
INTERVENTION_TOGGLE_KEY="9"
EPISODE_START_KEY="pagedown"
EPISODE_END_KEY="end"
EPISODE_DISCARD_KEY="home"
EPISODE_SUCCESS_KEY="["
EPISODE_FAILURE_KEY="]"
ACP_CFG_BETA="1.5"

CLOUD_NUM_PROCESSES="8"
CLOUD_MIXED_PRECISION="bf16"
CLOUD_CUDA_VISIBLE_DEVICES=""

VALUE_STEPS="8000"
VALUE_BATCH_SIZE="16"
VALUE_NUM_WORKERS="8"
VALUE_SAVE_FREQ="2000"
VALUE_LOG_FREQ="100"
VALUE_C_FAIL_COEF="1.0"

INFER_BATCH_SIZE="256"
INFER_NUM_WORKERS="8"
ACP_N_STEP="50"
ACP_POSITIVE_RATIO="0.3"
ACP_FORCE_INTERVENTION_POSITIVE="true"
ACP_C_FAIL_COEF="1.0"

ACP_STEPS="12000"
ACP_BATCH_SIZE="8"
ACP_SAVE_FREQ="2000"
ACP_LOG_FREQ="100"
ACP_INDICATOR_DROPOUT_PROB="0.3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    --task-name)
      TASK_NAME="$2"
      shift 2
      ;;
    --recap-repo-id)
      RECAP_REPO_ID="$2"
      shift 2
      ;;
    --eval-repo-id)
      EVAL_REPO_ID="$2"
      shift 2
      ;;
    --local-project-root)
      LOCAL_PROJECT_ROOT="$2"
      shift 2
      ;;
    --cloud-project-root)
      CLOUD_PROJECT_ROOT="$2"
      shift 2
      ;;
    --dataset-root-local)
      DATASET_ROOT_LOCAL="$2"
      shift 2
      ;;
    --dataset-root-cloud)
      DATASET_ROOT_CLOUD="$2"
      shift 2
      ;;
    --base-policy-path-local)
      BASE_POLICY_PATH_LOCAL="$2"
      shift 2
      ;;
    --base-policy-path-cloud)
      BASE_POLICY_PATH_CLOUD="$2"
      shift 2
      ;;
    --value-out-cloud-root)
      VALUE_OUT_CLOUD_ROOT="$2"
      shift 2
      ;;
    --acp-out-cloud-root)
      ACP_OUT_CLOUD_ROOT="$2"
      shift 2
      ;;
    --acp-out-local-root)
      ACP_OUT_LOCAL_ROOT="$2"
      shift 2
      ;;
    --cloud-ssh)
      CLOUD_SSH="$2"
      shift 2
      ;;
    --cloud-rsync-ssh-opts)
      CLOUD_RSYNC_SSH_OPTS="$2"
      shift 2
      ;;
    --allow-existing-dst)
      ALLOW_EXISTING_DST="$2"
      shift 2
      ;;
    --camera-env)
      CAMERA_ENV="$2"
      shift 2
      ;;
    --dataset-single-task)
      DATASET_SINGLE_TASK="$2"
      shift 2
      ;;
    --dataset-num-episodes)
      DATASET_NUM_EPISODES="$2"
      shift 2
      ;;
    --dataset-num-episodes-eval)
      DATASET_NUM_EPISODES_EVAL="$2"
      shift 2
      ;;
    --dataset-episode-time-s)
      DATASET_EPISODE_TIME_S="$2"
      shift 2
      ;;
    --dataset-reset-time-s)
      DATASET_RESET_TIME_S="$2"
      shift 2
      ;;
    --dataset-vcodec)
      DATASET_VCODEC="$2"
      shift 2
      ;;
    --display-data)
      DISPLAY_DATA="$2"
      shift 2
      ;;
    --play-sounds)
      PLAY_SOUNDS="$2"
      shift 2
      ;;
    --intervention-toggle-key)
      INTERVENTION_TOGGLE_KEY="$2"
      shift 2
      ;;
    --episode-start-key)
      EPISODE_START_KEY="$2"
      shift 2
      ;;
    --episode-end-key)
      EPISODE_END_KEY="$2"
      shift 2
      ;;
    --episode-discard-key)
      EPISODE_DISCARD_KEY="$2"
      shift 2
      ;;
    --episode-success-key)
      EPISODE_SUCCESS_KEY="$2"
      shift 2
      ;;
    --episode-failure-key)
      EPISODE_FAILURE_KEY="$2"
      shift 2
      ;;
    --acp-cfg-beta)
      ACP_CFG_BETA="$2"
      shift 2
      ;;
    --cloud-num-processes)
      CLOUD_NUM_PROCESSES="$2"
      shift 2
      ;;
    --cloud-mixed-precision)
      CLOUD_MIXED_PRECISION="$2"
      shift 2
      ;;
    --cloud-cuda-visible-devices)
      CLOUD_CUDA_VISIBLE_DEVICES="$2"
      shift 2
      ;;
    --value-steps)
      VALUE_STEPS="$2"
      shift 2
      ;;
    --value-batch-size)
      VALUE_BATCH_SIZE="$2"
      shift 2
      ;;
    --value-num-workers)
      VALUE_NUM_WORKERS="$2"
      shift 2
      ;;
    --value-save-freq)
      VALUE_SAVE_FREQ="$2"
      shift 2
      ;;
    --value-log-freq)
      VALUE_LOG_FREQ="$2"
      shift 2
      ;;
    --value-c-fail-coef)
      VALUE_C_FAIL_COEF="$2"
      shift 2
      ;;
    --infer-batch-size)
      INFER_BATCH_SIZE="$2"
      shift 2
      ;;
    --infer-num-workers)
      INFER_NUM_WORKERS="$2"
      shift 2
      ;;
    --acp-n-step)
      ACP_N_STEP="$2"
      shift 2
      ;;
    --acp-positive-ratio)
      ACP_POSITIVE_RATIO="$2"
      shift 2
      ;;
    --acp-force-intervention-positive)
      ACP_FORCE_INTERVENTION_POSITIVE="$2"
      shift 2
      ;;
    --acp-c-fail-coef)
      ACP_C_FAIL_COEF="$2"
      shift 2
      ;;
    --acp-steps)
      ACP_STEPS="$2"
      shift 2
      ;;
    --acp-batch-size)
      ACP_BATCH_SIZE="$2"
      shift 2
      ;;
    --acp-save-freq)
      ACP_SAVE_FREQ="$2"
      shift 2
      ;;
    --acp-log-freq)
      ACP_LOG_FREQ="$2"
      shift 2
      ;;
    --acp-indicator-dropout-prob)
      ACP_INDICATOR_DROPOUT_PROB="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_err "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${RUN_ID}" ]]; then
  RUN_ID="$(date +%F_%H-%M-%S)"
fi
if [[ -z "${RECAP_REPO_ID}" ]]; then
  RECAP_REPO_ID="local/${TASK_NAME}_r1_${RUN_ID}"
fi
if [[ -z "${EVAL_REPO_ID}" ]]; then
  EVAL_REPO_ID="local/${TASK_NAME}_eval_${RUN_ID}"
fi
if [[ -z "${BASE_POLICY_PATH_CLOUD}" ]]; then
  BASE_POLICY_PATH_CLOUD="${BASE_POLICY_PATH_LOCAL}"
fi

normalize_bool ALLOW_EXISTING_DST
normalize_bool DISPLAY_DATA
normalize_bool PLAY_SOUNDS
normalize_bool ACP_FORCE_INTERVENTION_POSITIVE

RECAP_DATASET_DIR_LOCAL="$(resolve_repo_dir "${DATASET_ROOT_LOCAL}" "${RECAP_REPO_ID}")"
RECAP_DATASET_DIR_CLOUD="$(resolve_repo_dir "${DATASET_ROOT_CLOUD}" "${RECAP_REPO_ID}")"
EVAL_DATASET_DIR_LOCAL="$(resolve_repo_dir "${DATASET_ROOT_LOCAL}" "${EVAL_REPO_ID}")"

VALUE_OUT_CLOUD="${VALUE_OUT_CLOUD_ROOT%/}/${RUN_ID}"
ACP_OUT_CLOUD="${ACP_OUT_CLOUD_ROOT%/}/${RUN_ID}"
ACP_OUT_LOCAL="${ACP_OUT_LOCAL_ROOT%/}/${RUN_ID}"
ACP_POLICY_PATH_LOCAL="${ACP_OUT_LOCAL}/checkpoints/last/pretrained_model"

case "${ACTION}" in
  collect)
    run_collect
    ;;
  sync-up)
    run_sync_up
    ;;
  value-train)
    run_value_train
    ;;
  value-infer)
    run_value_infer
    ;;
  acp-train)
    run_acp_train
    ;;
  sync-down)
    run_sync_down
    ;;
  eval)
    run_eval
    ;;
  *)
    log_err "Unknown command: ${ACTION}"
    usage
    exit 2
    ;;
esac
