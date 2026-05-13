#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/training/trainpi05.sh <command> [options]

Commands:
  env      Create uv virtual env and install pi dependencies.
  bootstrap Run env+check and optional HF login.
  check    Verify runtime (python/accelerate/transformers siglip patch).
  login    Run Hugging Face login in .venv.
  smoke    Run 1-GPU smoke training (default: 5 steps).
  train    Run multi-GPU full training (default: 30000 steps, 6 GPUs).

Common options:
  --dataset-root PATH       Dataset root directory.
  --output-root PATH        Output root directory.
  --run-id ID               Explicit run id. Default: current timestamp.
  --run-tag TAG             Output suffix tag. Defaults by command.
  --batch-size N            Batch size. Default: 8
  --steps N                 Training steps. Defaults by command.
  --cuda-visible-devices S  CUDA_VISIBLE_DEVICES string. Defaults by command.
  --num-processes N         accelerate --num_processes. Defaults by command.
  --save-freq N             Checkpoint save frequency. Default: 5000
  --log-freq N              Training log frequency. Default: 10
  --compile-model BOOL      policy.compile_model (true/false). Defaults by command.
  --compile-mode MODE       policy.compile_mode. Optional (e.g. reduce-overhead).
  --mixed-precision MODE    accelerate mixed precision. Default: bf16
  --wandb-enable BOOL       wandb.enable (true/false). Default: false
  --wandb-api-key KEY       Set WANDB_API_KEY for this run (optional).
  --wandb-project NAME      Set wandb.project for this run (optional).
  --pretrained-path PATH    Pretrained policy path. Default: lerobot/pi05_base
  --proxy                   Export default http/https proxy.
  --http-proxy URL          Explicit http proxy URL (implies --proxy).
  --https-proxy URL         Explicit https proxy URL (implies --proxy).
  --hf-home PATH            Shared HF cache root. Default: /media/jushen/stone-shi/hf_home
  --no-persistent-hf-home   Disable default shared HF cache path.
  --offline                 Force offline mode (HF_HUB_OFFLINE=1, TRANSFORMERS_OFFLINE=1).
  --online                  Disable offline mode for this run (allow network access).
  --hf-token TOKEN          HF token for non-interactive login command.
  -h, --help                Show this help.

Examples:
  bash scripts/training/trainpi05.sh bootstrap --proxy --hf-token "hf_xxx"
  bash scripts/training/trainpi05.sh env --proxy
  bash scripts/training/trainpi05.sh check
  bash scripts/training/trainpi05.sh login --hf-token "hf_xxx"
  bash scripts/training/trainpi05.sh smoke --steps 5 --proxy
  bash scripts/training/trainpi05.sh train --num-processes 6 --cuda-visible-devices 0,1,2,3,4,5
  bash scripts/training/trainpi05.sh train --online --proxy --num-processes 1 --cuda-visible-devices 0 --steps 1
  bash scripts/training/trainpi05.sh train --num-processes 6 --cuda-visible-devices 0,1,2,3,4,5 --save-freq 5000
  bash scripts/training/trainpi05.sh train --num-processes 1 --cuda-visible-devices 0 --steps 200 --compile-model false --run-tag fastcheck
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VENV_PYTHON_BIN="${PROJECT_ROOT}/.venv/bin/python"
VENV_ACCELERATE_BIN="${PROJECT_ROOT}/.venv/bin/accelerate"
VENV_HF_BIN="${PROJECT_ROOT}/.venv/bin/hf"
PYTHON_BIN="${VENV_PYTHON_BIN}"
ACCELERATE_BIN="${VENV_ACCELERATE_BIN}"
HF_BIN="${VENV_HF_BIN}"

ACTION="${1:-}"
if [[ -z "${ACTION}" ]]; then
  usage
  exit 2
fi
if [[ "${ACTION}" == "-h" || "${ACTION}" == "--help" || "${ACTION}" == "help" ]]; then
  usage
  exit 0
fi
shift || true

DATASET_ROOT="/media/jushen/stone-shi/lerobot_v30/put_the_phone_stand_into_the_shipping_box0509_2208"
OUTPUT_ROOT="/media/jushen/stone-shi/checkpoints/lerobotpi06"
PRETRAINED_PATH="lerobot/pi05_base"
BATCH_SIZE="8"
STEPS=""
RUN_ID=""
RUN_TAG=""
CUDA_VISIBLE_DEVICES_VALUE=""
NUM_PROCESSES=""
SAVE_FREQ="5000"
LOG_FREQ="10"
COMPILE_MODEL=""
COMPILE_MODE=""
MIXED_PRECISION="bf16"
WANDB_ENABLE="false"
WANDB_API_KEY_VALUE=""
WANDB_PROJECT="${WANDB_PROJECT:-}"

ENABLE_PROXY="false"
ENABLE_OFFLINE="true"
HTTP_PROXY_VALUE="http://192.168.32.28:18000"
HTTPS_PROXY_VALUE="http://192.168.32.28:18000"
HF_TOKEN=""
ENABLE_PERSISTENT_HF_HOME="true"
HF_HOME_VALUE="/media/jushen/stone-shi/hf_home"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dataset-root)
      DATASET_ROOT="$2"
      shift 2
      ;;
    --output-root)
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    --run-tag)
      RUN_TAG="$2"
      shift 2
      ;;
    --batch-size)
      BATCH_SIZE="$2"
      shift 2
      ;;
    --steps)
      STEPS="$2"
      shift 2
      ;;
    --cuda-visible-devices)
      CUDA_VISIBLE_DEVICES_VALUE="$2"
      shift 2
      ;;
    --num-processes)
      NUM_PROCESSES="$2"
      shift 2
      ;;
    --save-freq|--savefreq)
      SAVE_FREQ="$2"
      shift 2
      ;;
    --log-freq|--logfreq)
      LOG_FREQ="$2"
      shift 2
      ;;
    --compile-model)
      COMPILE_MODEL="$2"
      shift 2
      ;;
    --compile-mode)
      COMPILE_MODE="$2"
      shift 2
      ;;
    --mixed-precision)
      MIXED_PRECISION="$2"
      shift 2
      ;;
    --wandb-enable)
      WANDB_ENABLE="$2"
      shift 2
      ;;
    --wandb-api-key)
      WANDB_API_KEY_VALUE="$2"
      shift 2
      ;;
    --wandb-project)
      WANDB_PROJECT="$2"
      shift 2
      ;;
    --pretrained-path)
      PRETRAINED_PATH="$2"
      shift 2
      ;;
    --proxy)
      ENABLE_PROXY="true"
      shift
      ;;
    --http-proxy)
      ENABLE_PROXY="true"
      HTTP_PROXY_VALUE="$2"
      shift 2
      ;;
    --https-proxy)
      ENABLE_PROXY="true"
      HTTPS_PROXY_VALUE="$2"
      shift 2
      ;;
    --hf-home)
      HF_HOME_VALUE="$2"
      shift 2
      ;;
    --no-persistent-hf-home)
      ENABLE_PERSISTENT_HF_HOME="false"
      shift
      ;;
    --offline)
      ENABLE_OFFLINE="true"
      shift
      ;;
    --online)
      ENABLE_OFFLINE="false"
      shift
      ;;
    --hf-token)
      HF_TOKEN="$2"
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

apply_proxy_if_needed() {
  if [[ "${ENABLE_PROXY}" == "true" ]]; then
    export http_proxy="${HTTP_PROXY_VALUE}"
    export https_proxy="${HTTPS_PROXY_VALUE}"
    log_info "http_proxy=${http_proxy}"
    log_info "https_proxy=${https_proxy}"
  fi
}

apply_offline_if_needed() {
  if [[ "${ENABLE_OFFLINE}" == "true" ]]; then
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1
    export HF_DATASETS_OFFLINE=1
    log_info "HF_HUB_OFFLINE=${HF_HUB_OFFLINE}"
    log_info "TRANSFORMERS_OFFLINE=${TRANSFORMERS_OFFLINE}"
    log_info "HF_DATASETS_OFFLINE=${HF_DATASETS_OFFLINE}"
  else
    export HF_HUB_OFFLINE=0
    export TRANSFORMERS_OFFLINE=0
    export HF_DATASETS_OFFLINE=0
    log_info "offline disabled for this run (HF_HUB_OFFLINE=${HF_HUB_OFFLINE})"
  fi
}

apply_hf_home_if_needed() {
  if [[ "${ENABLE_PERSISTENT_HF_HOME}" == "true" ]]; then
    mkdir -p "${HF_HOME_VALUE}"
    export HF_HOME="${HF_HOME_VALUE}"
    export HUGGINGFACE_HUB_CACHE="${HF_HOME}/hub"
    export HF_HUB_CACHE="${HUGGINGFACE_HUB_CACHE}"
    export HF_DATASETS_CACHE="${HF_HOME}/datasets"
    log_info "HF_HOME=${HF_HOME}"
    log_info "HUGGINGFACE_HUB_CACHE=${HUGGINGFACE_HUB_CACHE}"
  fi
}

apply_wandb_env_if_needed() {
  if [[ -n "${WANDB_API_KEY_VALUE}" ]]; then
    export WANDB_API_KEY="${WANDB_API_KEY_VALUE}"
    log_info "WANDB_API_KEY loaded from --wandb-api-key"
  elif [[ -n "${WANDB_API_KEY:-}" ]]; then
    log_info "WANDB_API_KEY detected from environment"
  fi
  if [[ -n "${WANDB_PROJECT}" ]]; then
    log_info "WANDB project set to '${WANDB_PROJECT}'"
  fi
}

require_executable() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    log_err "${path} 不存在或不可执行。"
    return 1
  fi
}

resolve_runtime_binaries() {
  local py_candidate=""
  if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/python" ]] && "${CONDA_PREFIX}/bin/python" -V > /dev/null 2>&1; then
    py_candidate="${CONDA_PREFIX}/bin/python"
    log_info "use conda python=${py_candidate}"
  elif [[ -x "${VENV_PYTHON_BIN}" ]] && "${VENV_PYTHON_BIN}" -V > /dev/null 2>&1; then
    py_candidate="${VENV_PYTHON_BIN}"
  elif command -v python > /dev/null 2>&1; then
    py_candidate="$(command -v python)"
    log_info "fallback python=${py_candidate} (.venv/bin/python 不可用)"
  elif command -v python3 > /dev/null 2>&1; then
    py_candidate="$(command -v python3)"
    log_info "fallback python3=${py_candidate} (.venv/bin/python 不可用)"
  else
    log_err "未找到可用 python。请先准备 .venv 或确保 PATH 中有 python/python3。"
    return 1
  fi
  PYTHON_BIN="${py_candidate}"

  local acc_candidate=""
  if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/accelerate" ]] && "${CONDA_PREFIX}/bin/accelerate" --help > /dev/null 2>&1; then
    acc_candidate="${CONDA_PREFIX}/bin/accelerate"
    log_info "use conda accelerate=${acc_candidate}"
  elif [[ -x "${VENV_ACCELERATE_BIN}" ]] && "${VENV_ACCELERATE_BIN}" --help > /dev/null 2>&1; then
    acc_candidate="${VENV_ACCELERATE_BIN}"
  elif command -v accelerate > /dev/null 2>&1; then
    acc_candidate="$(command -v accelerate)"
    log_info "fallback accelerate=${acc_candidate} (.venv/bin/accelerate 不可用)"
  else
    log_err "未找到可用 accelerate。请安装 accelerate 或激活含 accelerate 的环境。"
    return 1
  fi
  ACCELERATE_BIN="${acc_candidate}"

  local hf_candidate=""
  if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/hf" ]] && "${CONDA_PREFIX}/bin/hf" --help > /dev/null 2>&1; then
    hf_candidate="${CONDA_PREFIX}/bin/hf"
    log_info "use conda hf=${hf_candidate}"
  elif [[ -x "${VENV_HF_BIN}" ]] && "${VENV_HF_BIN}" --help > /dev/null 2>&1; then
    hf_candidate="${VENV_HF_BIN}"
  elif command -v hf > /dev/null 2>&1; then
    hf_candidate="$(command -v hf)"
    log_info "fallback hf=${hf_candidate} (.venv/bin/hf 不可用)"
  else
    hf_candidate=""
  fi
  HF_BIN="${hf_candidate}"
}

check_siglip_patch() {
  "${PYTHON_BIN}" -c "import transformers; from transformers.models.siglip import check; ok=check.check_whether_transformers_replace_is_installed_correctly(); print('transformers:', transformers.__version__); print('siglip patch ok:', ok); raise SystemExit(0 if ok else 1)"
}

resolve_hf_hub_cache_root() {
  if [[ -n "${HUGGINGFACE_HUB_CACHE:-}" ]]; then
    printf '%s\n' "${HUGGINGFACE_HUB_CACHE}"
    return 0
  fi
  if [[ -n "${HF_HOME:-}" ]]; then
    printf '%s\n' "${HF_HOME}/hub"
    return 0
  fi
  printf '%s\n' "${HOME}/.cache/huggingface/hub"
}

ensure_offline_pretrained_available() {
  local pretrained_path="$1"
  if [[ -e "${pretrained_path}" ]]; then
    log_info "offline pretrained path exists: ${pretrained_path}"
    return 0
  fi

  local hub_root
  hub_root="$(resolve_hf_hub_cache_root)"
  local model_cache_dir="${hub_root}/models--${pretrained_path//\//--}"

  if [[ ! -d "${model_cache_dir}/snapshots" ]]; then
    log_err "离线模式下未找到预训练模型缓存: ${model_cache_dir}"
    log_err "可先临时联网预热一次：bash scripts/training/trainpi05.sh smoke --online --proxy --steps 1 --cuda-visible-devices 0"
    return 1
  fi

  if ! compgen -G "${model_cache_dir}/snapshots/*" > /dev/null; then
    log_err "离线模式下模型缓存为空: ${model_cache_dir}/snapshots"
    log_err "可先临时联网预热一次：bash scripts/training/trainpi05.sh smoke --online --proxy --steps 1 --cuda-visible-devices 0"
    return 1
  fi

  log_info "offline cache detected: ${model_cache_dir}"
}

run_env_setup() {
  cd "${PROJECT_ROOT}"
  apply_proxy_if_needed
  apply_hf_home_if_needed

  log_info "project_root=${PROJECT_ROOT}"
  uv python install 3.10
  uv venv --python 3.10 --clear .venv
  uv pip install --python "${VENV_PYTHON_BIN}" -U pip setuptools wheel
  uv pip install --python "${VENV_PYTHON_BIN}" -e ".[pi]"

  run_check
}

run_bootstrap() {
  run_env_setup
  if [[ -n "${HF_TOKEN}" ]]; then
    run_login
  else
    log_info "未提供 --hf-token，已跳过 HF 登录。可后续手动执行 login。"
  fi
}

run_check() {
  cd "${PROJECT_ROOT}"
  apply_proxy_if_needed
  apply_hf_home_if_needed
  apply_offline_if_needed

  resolve_runtime_binaries
  require_executable "${PYTHON_BIN}"
  require_executable "${ACCELERATE_BIN}"
  if [[ "${ENABLE_OFFLINE}" == "true" ]]; then
    ensure_offline_pretrained_available "${PRETRAINED_PATH}" || return 1
  fi

  log_info "python=${PYTHON_BIN}"
  log_info "accelerate=${ACCELERATE_BIN}"
  "${PYTHON_BIN}" -V
  check_siglip_patch
  "${ACCELERATE_BIN}" env
}

run_login() {
  cd "${PROJECT_ROOT}"
  apply_proxy_if_needed
  apply_hf_home_if_needed

  resolve_runtime_binaries
  if [[ -z "${HF_BIN}" ]]; then
    log_err "未找到可用 hf 命令。请先安装 huggingface_hub CLI（`hf`）。"
    return 1
  fi
  require_executable "${HF_BIN}"

  if [[ -n "${HF_TOKEN}" ]]; then
    "${HF_BIN}" auth login --token "${HF_TOKEN}"
  else
    "${HF_BIN}" auth login
  fi
  local max_retry=3
  local attempt=1
  local whoami_ok="false"
  while [[ "${attempt}" -le "${max_retry}" ]]; do
    if "${HF_BIN}" auth whoami; then
      whoami_ok="true"
      break
    fi
    log_err "hf auth whoami 失败（attempt ${attempt}/${max_retry}），可能是代理链路瞬时 TLS 抖动。"
    if [[ "${attempt}" -lt "${max_retry}" ]]; then
      sleep 2
    fi
    attempt=$((attempt + 1))
  done
  if [[ "${whoami_ok}" != "true" ]]; then
    log_err "whoami 校验失败，但 token 可能已成功写入本地。"
    log_info "可稍后手动重试：${HF_BIN} auth whoami"
    log_info "若训练走离线缓存，可继续执行；若需联网拉新模型，建议先确认代理稳定。"
  fi
}

run_training() {
  local mode="$1"  # smoke | train
  cd "${PROJECT_ROOT}"
  apply_proxy_if_needed
  apply_hf_home_if_needed
  apply_offline_if_needed

  resolve_runtime_binaries
  require_executable "${PYTHON_BIN}"
  require_executable "${ACCELERATE_BIN}"

  if [[ "${mode}" == "smoke" ]]; then
    local default_steps="5"
    local default_gpus="0"
    local default_num_processes="1"
    local default_tag="1gpu_smoke"
    local default_compile_model="false"
  else
    local default_steps="30000"
    local default_gpus="0,1,2,3,4,5"
    local default_num_processes="6"
    local default_tag="8gpu"
    local default_compile_model="true"
  fi

  if [[ -z "${STEPS}" ]]; then
    STEPS="${default_steps}"
  fi
  if [[ -z "${CUDA_VISIBLE_DEVICES_VALUE}" ]]; then
    CUDA_VISIBLE_DEVICES_VALUE="${default_gpus}"
  fi
  if [[ -z "${NUM_PROCESSES}" ]]; then
    NUM_PROCESSES="${default_num_processes}"
  fi
  if [[ -z "${RUN_TAG}" ]]; then
    RUN_TAG="${default_tag}"
  fi
  if [[ -z "${COMPILE_MODEL}" ]]; then
    COMPILE_MODEL="${default_compile_model}"
  fi
  if [[ -z "${RUN_ID}" ]]; then
    RUN_ID="$(date +%F_%H-%M-%S)"
  fi
  COMPILE_MODEL="${COMPILE_MODEL,,}"
  if [[ "${COMPILE_MODEL}" != "true" && "${COMPILE_MODEL}" != "false" ]]; then
    log_err "--compile-model 仅支持 true/false，收到: ${COMPILE_MODEL}"
    return 2
  fi
  WANDB_ENABLE="${WANDB_ENABLE,,}"
  if [[ "${WANDB_ENABLE}" != "true" && "${WANDB_ENABLE}" != "false" ]]; then
    log_err "--wandb-enable 仅支持 true/false，收到: ${WANDB_ENABLE}"
    return 2
  fi
  if [[ "${COMPILE_MODEL}" == "false" && -n "${COMPILE_MODE}" ]]; then
    log_info "compile_model=false，将忽略 compile_mode=${COMPILE_MODE}"
  fi
  apply_wandb_env_if_needed
  if [[ "${WANDB_ENABLE}" == "true" && -z "${WANDB_API_KEY:-}" ]]; then
    log_warn "wandb is enabled but WANDB_API_KEY is empty. Ensure wandb login exists in this container."
  fi
  if [[ "${WANDB_ENABLE}" == "true" && -z "${WANDB_PROJECT}" ]]; then
    log_warn "wandb is enabled but --wandb-project/WANDB_PROJECT is empty. It will fallback to config default."
  fi

  if [[ ! -d "${DATASET_ROOT}" ]]; then
    log_err "数据集目录不存在: ${DATASET_ROOT}"
    return 1
  fi

  if [[ "${ENABLE_OFFLINE}" == "true" ]]; then
    ensure_offline_pretrained_available "${PRETRAINED_PATH}" || return 1
  fi

  mkdir -p "${OUTPUT_ROOT}"

  local repo_id
  repo_id="$(basename "${DATASET_ROOT}")"
  local output_dir="${OUTPUT_ROOT}/${RUN_ID}_pi05_${RUN_TAG}"
  local job_name="${RUN_ID}_pi05_${repo_id}_${RUN_TAG}"
  local log_file="${OUTPUT_ROOT}/${RUN_ID}_pi05_${RUN_TAG}.log"
  local wandb_output_log="${output_dir}/wandb/latest-run/files/output.log"

  if [[ -e "${output_dir}" ]]; then
    log_err "输出目录已存在，已停止以避免覆盖: ${output_dir}"
    return 1
  fi

  check_siglip_patch

  log_info "python=${PYTHON_BIN}"
  log_info "accelerate=${ACCELERATE_BIN}"
  log_info "dataset_root=${DATASET_ROOT}"
  log_info "output_dir=${output_dir}"
  log_info "log_file=${log_file}"
  log_info "tail_log_cmd=tail -f \"${log_file}\""
  log_info "cuda_visible_devices=${CUDA_VISIBLE_DEVICES_VALUE}"
  log_info "num_processes=${NUM_PROCESSES}"
  log_info "save_freq=${SAVE_FREQ}"
  log_info "log_freq=${LOG_FREQ}"
  log_info "compile_model=${COMPILE_MODEL}"
  if [[ -n "${COMPILE_MODE}" ]]; then
    log_info "compile_mode=${COMPILE_MODE}"
  fi
  log_info "steps=${STEPS}"
  log_info "batch_size=${BATCH_SIZE}"
  log_info "wandb_enable=${WANDB_ENABLE}"
  if [[ -n "${WANDB_PROJECT}" ]]; then
    log_info "wandb_project=${WANDB_PROJECT}"
  else
    log_info "wandb_project=<config-default>"
  fi
  if [[ "${WANDB_ENABLE}" == "true" ]]; then
    log_info "wandb_output_log=${wandb_output_log}"
    log_info "tail_wandb_log_cmd=tail -f \"${wandb_output_log}\""
  fi

  local -a launch_args
  launch_args=(
    launch
    "--num_processes=${NUM_PROCESSES}"
    "--mixed_precision=${MIXED_PRECISION}"
  )
  if [[ "${NUM_PROCESSES}" -gt 1 ]]; then
    launch_args+=(--multi_gpu)
  fi
  launch_args+=(
    src/lerobot/scripts/lerobot_train.py
    "--dataset.root=${DATASET_ROOT}"
    "--dataset.repo_id=${repo_id}"
    "--policy.type=pi05"
    "--policy.pretrained_path=${PRETRAINED_PATH}"
    "--policy.dtype=bfloat16"
    "--policy.gradient_checkpointing=true"
    "--policy.compile_model=${COMPILE_MODEL}"
    "--batch_size=${BATCH_SIZE}"
    "--steps=${STEPS}"
    "--log_freq=${LOG_FREQ}"
    "--save_freq=${SAVE_FREQ}"
    "--output_dir=${output_dir}"
    "--job_name=${job_name}"
    "--policy.push_to_hub=false"
    "--wandb.enable=${WANDB_ENABLE}"
  )
  if [[ -n "${WANDB_PROJECT}" ]]; then
    launch_args+=("--wandb.project=${WANDB_PROJECT}")
  fi
  if [[ "${COMPILE_MODEL}" == "true" && -n "${COMPILE_MODE}" ]]; then
    launch_args+=("--policy.compile_mode=${COMPILE_MODE}")
  fi

  set +e
  CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES_VALUE}" \
  PYTHONPATH=src \
  "${ACCELERATE_BIN}" "${launch_args[@]}" 2>&1 | tee "${log_file}"
  local exit_code="${PIPESTATUS[0]}"
  set -e

  if [[ "${exit_code}" -ne 0 ]]; then
    log_err "训练失败，exit_code=${exit_code}，日志: ${log_file}"
    return "${exit_code}"
  fi

  log_info "训练完成。输出目录: ${output_dir}"
}

case "${ACTION}" in
  env)
    run_env_setup
    ;;
  bootstrap)
    run_bootstrap
    ;;
  check)
    run_check
    ;;
  login)
    run_login
    ;;
  smoke)
    run_training smoke
    ;;
  train)
    run_training train
    ;;
  *)
    log_err "Unknown command: ${ACTION}"
    usage
    exit 2
    ;;
esac
