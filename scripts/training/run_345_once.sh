#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/training/run_345_once.sh [options]

Description:
  Run RECAP-lite stages 3/4/5 in order:
    value-train -> value-infer -> acp-train

Presets:
  single_4090_nearprod  Default. Single RTX4090 near-production budget.
  single_a100_nearprod  Single A100 near-production budget.
  single_a100_smoke     Fast smoke test on single GPU.
  four_gpu_prod         4-GPU production style.
  eight_gpu_prod        8-GPU production style (same as recap-lite defaults).

Core options:
  --preset NAME
  --run-id ID
  --recap-repo-id ID
  --cloud-project-root PATH
  --dataset-root-cloud PATH
  --base-policy-path-cloud PATH
  --value-out-cloud-root PATH
  --acp-out-cloud-root PATH
  --allow-existing-dst true|false
  --dry-run

Scale options:
  --auto-scale-steps true|false
  --cloud-num-processes N
  --cloud-cuda-visible-devices IDS
  --cloud-mixed-precision MODE
  --value-steps N
  --value-batch-size N
  --value-num-workers N
  --acp-steps N
  --acp-batch-size N
  --infer-batch-size N
  --infer-num-workers N

Examples:
  # 1) Single-GPU smoke test (no execution, print commands only)
  bash scripts/training/run_345_once.sh \
    --preset single_a100_smoke \
    --recap-repo-id local/so101_recap_lite_r1_2026-05-14_15-00-00 \
    --base-policy-path-cloud /path/to/pi05_ft/checkpoints/005000/pretrained_model \
    --dry-run

  # 2) Single-GPU near-production run (default preset: RTX4090)
  bash scripts/training/run_345_once.sh \
    --preset single_4090_nearprod \
    --recap-repo-id local/so101_recap_lite_r1_2026-05-14_15-00-00 \
    --base-policy-path-cloud /path/to/pi05_ft/checkpoints/005000/pretrained_model

  # 3) 4-GPU run with explicit ids
  bash scripts/training/run_345_once.sh \
    --preset four_gpu_prod \
    --cloud-cuda-visible-devices 0,1,2,3 \
    --recap-repo-id local/so101_recap_lite_r1_2026-05-14_15-00-00 \
    --base-policy-path-cloud /path/to/pi05_ft/checkpoints/005000/pretrained_model
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

require_non_empty() {
  local value="$1"
  local label="$2"
  if [[ -z "${value}" ]]; then
    log_err "${label} is required."
    exit 2
  fi
}

require_positive_int() {
  local value="$1"
  local label="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -le 0 ]]; then
    log_err "${label} must be a positive integer, got '${value}'."
    exit 2
  fi
}

print_cmd() {
  local -a cmd=("$@")
  printf '[CMD]'
  printf ' %q' "${cmd[@]}"
  printf '\n'
}

ceil_div() {
  local numerator="$1"
  local denominator="$2"
  echo $(( (numerator + denominator - 1) / denominator ))
}

run_stage() {
  local stage_name="$1"
  shift
  local -a cmd=("$@")
  log_info "===== ${stage_name} ====="
  print_cmd "${cmd[@]}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi
  "${cmd[@]}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DEFAULT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUN_RECAP_SCRIPT="${SCRIPT_DIR}/run_pi05_recap_lite.sh"

# Reference defaults from run_pi05_recap_lite.sh (8-GPU baseline).
REF_VALUE_STEPS=8000
REF_VALUE_BATCH_SIZE=16
REF_ACP_STEPS=12000
REF_ACP_BATCH_SIZE=8
REF_NUM_PROCESSES=8
REF_VALUE_EFFECTIVE_BS=$((REF_VALUE_BATCH_SIZE * REF_NUM_PROCESSES))
REF_ACP_EFFECTIVE_BS=$((REF_ACP_BATCH_SIZE * REF_NUM_PROCESSES))

PRESET="single_4090_nearprod"
RUN_ID="$(date +%F_%H-%M-%S)"
TASK_NAME="so101_recap_lite"
RECAP_REPO_ID=""

CLOUD_PROJECT_ROOT="${PROJECT_ROOT_DEFAULT}"
DATASET_ROOT_CLOUD="/media/jushen/stone-shi/lerobot_v30"
BASE_POLICY_PATH_CLOUD=""
VALUE_OUT_CLOUD_ROOT="/media/jushen/stone-shi/lerobot_pi06/checkpoints/value"
ACP_OUT_CLOUD_ROOT="/media/jushen/stone-shi/lerobot_pi06/checkpoints/acp"

ALLOW_EXISTING_DST="false"
DRY_RUN="false"
AUTO_SCALE_STEPS=""

# Preset-resolved runtime values.
CLOUD_NUM_PROCESSES=""
CLOUD_CUDA_VISIBLE_DEVICES=""
CLOUD_MIXED_PRECISION="bf16"
VALUE_STEPS=""
VALUE_BATCH_SIZE=""
VALUE_NUM_WORKERS="8"
ACP_STEPS=""
ACP_BATCH_SIZE=""
INFER_BATCH_SIZE=""
INFER_NUM_WORKERS="8"

# CLI overrides (applied after preset).
OVERRIDE_CLOUD_NUM_PROCESSES=""
OVERRIDE_CLOUD_CUDA_VISIBLE_DEVICES=""
OVERRIDE_CLOUD_MIXED_PRECISION=""
OVERRIDE_VALUE_STEPS=""
OVERRIDE_VALUE_BATCH_SIZE=""
OVERRIDE_VALUE_NUM_WORKERS=""
OVERRIDE_ACP_STEPS=""
OVERRIDE_ACP_BATCH_SIZE=""
OVERRIDE_INFER_BATCH_SIZE=""
OVERRIDE_INFER_NUM_WORKERS=""
OVERRIDE_AUTO_SCALE_STEPS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)
      PRESET="$2"
      shift 2
      ;;
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
    --cloud-project-root)
      CLOUD_PROJECT_ROOT="$2"
      shift 2
      ;;
    --dataset-root-cloud)
      DATASET_ROOT_CLOUD="$2"
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
    --allow-existing-dst)
      ALLOW_EXISTING_DST="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --auto-scale-steps)
      OVERRIDE_AUTO_SCALE_STEPS="$2"
      shift 2
      ;;
    --cloud-num-processes)
      OVERRIDE_CLOUD_NUM_PROCESSES="$2"
      shift 2
      ;;
    --cloud-cuda-visible-devices)
      OVERRIDE_CLOUD_CUDA_VISIBLE_DEVICES="$2"
      shift 2
      ;;
    --cloud-mixed-precision)
      OVERRIDE_CLOUD_MIXED_PRECISION="$2"
      shift 2
      ;;
    --value-steps)
      OVERRIDE_VALUE_STEPS="$2"
      shift 2
      ;;
    --value-batch-size)
      OVERRIDE_VALUE_BATCH_SIZE="$2"
      shift 2
      ;;
    --value-num-workers)
      OVERRIDE_VALUE_NUM_WORKERS="$2"
      shift 2
      ;;
    --acp-steps)
      OVERRIDE_ACP_STEPS="$2"
      shift 2
      ;;
    --acp-batch-size)
      OVERRIDE_ACP_BATCH_SIZE="$2"
      shift 2
      ;;
    --infer-batch-size)
      OVERRIDE_INFER_BATCH_SIZE="$2"
      shift 2
      ;;
    --infer-num-workers)
      OVERRIDE_INFER_NUM_WORKERS="$2"
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

apply_preset() {
  case "${PRESET}" in
    single_4090_nearprod)
      CLOUD_NUM_PROCESSES="1"
      CLOUD_CUDA_VISIBLE_DEVICES="0"
      VALUE_BATCH_SIZE="8"
      ACP_BATCH_SIZE="4"
      INFER_BATCH_SIZE="128"
      VALUE_NUM_WORKERS="4"
      INFER_NUM_WORKERS="4"
      AUTO_SCALE_STEPS="true"
      ;;
    single_a100_nearprod)
      CLOUD_NUM_PROCESSES="1"
      CLOUD_CUDA_VISIBLE_DEVICES="0"
      VALUE_BATCH_SIZE="16"
      ACP_BATCH_SIZE="8"
      INFER_BATCH_SIZE="256"
      VALUE_NUM_WORKERS="8"
      INFER_NUM_WORKERS="8"
      AUTO_SCALE_STEPS="true"
      ;;
    single_a100_smoke)
      CLOUD_NUM_PROCESSES="1"
      CLOUD_CUDA_VISIBLE_DEVICES="0"
      VALUE_BATCH_SIZE="8"
      VALUE_STEPS="500"
      VALUE_NUM_WORKERS="4"
      ACP_BATCH_SIZE="4"
      ACP_STEPS="1000"
      INFER_BATCH_SIZE="64"
      INFER_NUM_WORKERS="4"
      AUTO_SCALE_STEPS="false"
      ;;
    four_gpu_prod)
      CLOUD_NUM_PROCESSES="4"
      CLOUD_CUDA_VISIBLE_DEVICES="0,1,2,3"
      VALUE_BATCH_SIZE="16"
      ACP_BATCH_SIZE="8"
      INFER_BATCH_SIZE="256"
      VALUE_NUM_WORKERS="8"
      INFER_NUM_WORKERS="8"
      AUTO_SCALE_STEPS="true"
      ;;
    eight_gpu_prod)
      CLOUD_NUM_PROCESSES="8"
      CLOUD_CUDA_VISIBLE_DEVICES="0,1,2,3,4,5,6,7"
      VALUE_BATCH_SIZE="16"
      ACP_BATCH_SIZE="8"
      INFER_BATCH_SIZE="256"
      VALUE_NUM_WORKERS="8"
      INFER_NUM_WORKERS="8"
      AUTO_SCALE_STEPS="true"
      ;;
    *)
      log_err "Unknown preset: ${PRESET}"
      exit 2
      ;;
  esac
}

apply_preset

# Apply explicit CLI overrides.
[[ -n "${OVERRIDE_CLOUD_NUM_PROCESSES}" ]] && CLOUD_NUM_PROCESSES="${OVERRIDE_CLOUD_NUM_PROCESSES}"
[[ -n "${OVERRIDE_CLOUD_CUDA_VISIBLE_DEVICES}" ]] && CLOUD_CUDA_VISIBLE_DEVICES="${OVERRIDE_CLOUD_CUDA_VISIBLE_DEVICES}"
[[ -n "${OVERRIDE_CLOUD_MIXED_PRECISION}" ]] && CLOUD_MIXED_PRECISION="${OVERRIDE_CLOUD_MIXED_PRECISION}"
[[ -n "${OVERRIDE_VALUE_BATCH_SIZE}" ]] && VALUE_BATCH_SIZE="${OVERRIDE_VALUE_BATCH_SIZE}"
[[ -n "${OVERRIDE_ACP_BATCH_SIZE}" ]] && ACP_BATCH_SIZE="${OVERRIDE_ACP_BATCH_SIZE}"
[[ -n "${OVERRIDE_VALUE_NUM_WORKERS}" ]] && VALUE_NUM_WORKERS="${OVERRIDE_VALUE_NUM_WORKERS}"
[[ -n "${OVERRIDE_INFER_BATCH_SIZE}" ]] && INFER_BATCH_SIZE="${OVERRIDE_INFER_BATCH_SIZE}"
[[ -n "${OVERRIDE_INFER_NUM_WORKERS}" ]] && INFER_NUM_WORKERS="${OVERRIDE_INFER_NUM_WORKERS}"
[[ -n "${OVERRIDE_AUTO_SCALE_STEPS}" ]] && AUTO_SCALE_STEPS="${OVERRIDE_AUTO_SCALE_STEPS}"

normalize_bool ALLOW_EXISTING_DST
normalize_bool DRY_RUN
normalize_bool AUTO_SCALE_STEPS

require_non_empty "${RUN_ID}" "--run-id"
if [[ -z "${RECAP_REPO_ID}" ]]; then
  RECAP_REPO_ID="local/${TASK_NAME}_r1_${RUN_ID}"
  log_warn "--recap-repo-id missing, auto-generated: ${RECAP_REPO_ID}"
fi
require_non_empty "${BASE_POLICY_PATH_CLOUD}" "--base-policy-path-cloud"

require_positive_int "${CLOUD_NUM_PROCESSES}" "--cloud-num-processes"
require_positive_int "${VALUE_BATCH_SIZE}" "--value-batch-size"
require_positive_int "${ACP_BATCH_SIZE}" "--acp-batch-size"
require_positive_int "${INFER_BATCH_SIZE}" "--infer-batch-size"
require_positive_int "${VALUE_NUM_WORKERS}" "--value-num-workers"
require_positive_int "${INFER_NUM_WORKERS}" "--infer-num-workers"

CURRENT_VALUE_EFFECTIVE_BS=$((VALUE_BATCH_SIZE * CLOUD_NUM_PROCESSES))
CURRENT_ACP_EFFECTIVE_BS=$((ACP_BATCH_SIZE * CLOUD_NUM_PROCESSES))
SCALED_VALUE_STEPS="$(ceil_div $((REF_VALUE_STEPS * REF_VALUE_EFFECTIVE_BS)) "${CURRENT_VALUE_EFFECTIVE_BS}")"
SCALED_ACP_STEPS="$(ceil_div $((REF_ACP_STEPS * REF_ACP_EFFECTIVE_BS)) "${CURRENT_ACP_EFFECTIVE_BS}")"

if [[ "${AUTO_SCALE_STEPS}" == "true" ]]; then
  VALUE_STEPS="${SCALED_VALUE_STEPS}"
  ACP_STEPS="${SCALED_ACP_STEPS}"
fi

[[ -n "${OVERRIDE_VALUE_STEPS}" ]] && VALUE_STEPS="${OVERRIDE_VALUE_STEPS}"
[[ -n "${OVERRIDE_ACP_STEPS}" ]] && ACP_STEPS="${OVERRIDE_ACP_STEPS}"

require_positive_int "${VALUE_STEPS}" "--value-steps"
require_positive_int "${ACP_STEPS}" "--acp-steps"

ensure_file_exists "${RUN_RECAP_SCRIPT}" "run_pi05_recap_lite.sh"
ensure_dir_exists "${CLOUD_PROJECT_ROOT}" "cloud project root"
ensure_dir_exists "${DATASET_ROOT_CLOUD}" "dataset root cloud"
ensure_file_exists "${BASE_POLICY_PATH_CLOUD}/config.json" "base policy config (cloud)"
ensure_file_exists "${BASE_POLICY_PATH_CLOUD}/model.safetensors" "base policy weight (cloud)"

RECAP_DATASET_DIR_CLOUD="${DATASET_ROOT_CLOUD%/}/${RECAP_REPO_ID}"
VALUE_OUT_CLOUD="${VALUE_OUT_CLOUD_ROOT%/}/${RUN_ID}"
ACP_OUT_CLOUD="${ACP_OUT_CLOUD_ROOT%/}/${RUN_ID}"
ensure_dir_exists "${RECAP_DATASET_DIR_CLOUD}" "recap dataset dir (cloud)"

log_info "========== preflight =========="
log_info "preset=${PRESET}"
log_info "run_id=${RUN_ID}"
log_info "recap_repo_id=${RECAP_REPO_ID}"
log_info "cloud_project_root=${CLOUD_PROJECT_ROOT}"
log_info "dataset_root_cloud=${DATASET_ROOT_CLOUD}"
log_info "recap_dataset_dir_cloud=${RECAP_DATASET_DIR_CLOUD}"
log_info "base_policy_path_cloud=${BASE_POLICY_PATH_CLOUD}"
log_info "value_out_cloud=${VALUE_OUT_CLOUD}"
log_info "acp_out_cloud=${ACP_OUT_CLOUD}"
log_info "allow_existing_dst=${ALLOW_EXISTING_DST}"
log_info "dry_run=${DRY_RUN}"
log_info "cloud_num_processes=${CLOUD_NUM_PROCESSES}"
log_info "cloud_cuda_visible_devices=${CLOUD_CUDA_VISIBLE_DEVICES:-<empty>}"
log_info "cloud_mixed_precision=${CLOUD_MIXED_PRECISION}"
log_info "value_batch_size=${VALUE_BATCH_SIZE}, value_steps=${VALUE_STEPS}, value_num_workers=${VALUE_NUM_WORKERS}"
log_info "infer_batch_size=${INFER_BATCH_SIZE}, infer_num_workers=${INFER_NUM_WORKERS}"
log_info "acp_batch_size=${ACP_BATCH_SIZE}, acp_steps=${ACP_STEPS}"
log_info "reference_value_effective_bs=${REF_VALUE_EFFECTIVE_BS}, current_value_effective_bs=${CURRENT_VALUE_EFFECTIVE_BS}, scaled_value_steps=${SCALED_VALUE_STEPS}"
log_info "reference_acp_effective_bs=${REF_ACP_EFFECTIVE_BS}, current_acp_effective_bs=${CURRENT_ACP_EFFECTIVE_BS}, scaled_acp_steps=${SCALED_ACP_STEPS}"

if [[ -e "${VALUE_OUT_CLOUD}" ]]; then
  log_warn "value output already exists: ${VALUE_OUT_CLOUD}"
fi
if [[ -e "${ACP_OUT_CLOUD}" ]]; then
  log_warn "acp output already exists: ${ACP_OUT_CLOUD}"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  log_info "GPU inventory:"
  nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu --format=csv,noheader
else
  log_warn "nvidia-smi not found, skip GPU inventory."
fi

log_info "filesystem usage near dataset root:"
df -h "${DATASET_ROOT_CLOUD}"

cd "${CLOUD_PROJECT_ROOT}"

VALUE_TRAIN_CMD=(
  bash "${RUN_RECAP_SCRIPT}" value-train
  --run-id "${RUN_ID}"
  --recap-repo-id "${RECAP_REPO_ID}"
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}"
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}"
  --cloud-num-processes "${CLOUD_NUM_PROCESSES}"
  --cloud-mixed-precision "${CLOUD_MIXED_PRECISION}"
  --value-steps "${VALUE_STEPS}"
  --value-batch-size "${VALUE_BATCH_SIZE}"
  --value-num-workers "${VALUE_NUM_WORKERS}"
  --allow-existing-dst "${ALLOW_EXISTING_DST}"
)
if [[ -n "${CLOUD_CUDA_VISIBLE_DEVICES}" ]]; then
  VALUE_TRAIN_CMD+=(--cloud-cuda-visible-devices "${CLOUD_CUDA_VISIBLE_DEVICES}")
fi

VALUE_INFER_CMD=(
  bash "${RUN_RECAP_SCRIPT}" value-infer
  --run-id "${RUN_ID}"
  --recap-repo-id "${RECAP_REPO_ID}"
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}"
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}"
  --infer-batch-size "${INFER_BATCH_SIZE}"
  --infer-num-workers "${INFER_NUM_WORKERS}"
)

ACP_TRAIN_CMD=(
  bash "${RUN_RECAP_SCRIPT}" acp-train
  --run-id "${RUN_ID}"
  --recap-repo-id "${RECAP_REPO_ID}"
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}"
  --base-policy-path-cloud "${BASE_POLICY_PATH_CLOUD}"
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}"
  --cloud-num-processes "${CLOUD_NUM_PROCESSES}"
  --cloud-mixed-precision "${CLOUD_MIXED_PRECISION}"
  --acp-steps "${ACP_STEPS}"
  --acp-batch-size "${ACP_BATCH_SIZE}"
  --allow-existing-dst "${ALLOW_EXISTING_DST}"
)
if [[ -n "${CLOUD_CUDA_VISIBLE_DEVICES}" ]]; then
  ACP_TRAIN_CMD+=(--cloud-cuda-visible-devices "${CLOUD_CUDA_VISIBLE_DEVICES}")
fi

run_stage "stage-3 value-train" "${VALUE_TRAIN_CMD[@]}"
run_stage "stage-4 value-infer" "${VALUE_INFER_CMD[@]}"
run_stage "stage-5 acp-train" "${ACP_TRAIN_CMD[@]}"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_info "dry-run completed. No stage executed."
else
  log_info "run_345_once completed successfully."
fi
