#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/training/trainpi05_online_rl.sh <command> [options]

Commands:
  check    Verify online-RL runtime dependencies.
  learner  Start learner process for pi05 + online PPO (with value head).
  actor    Start actor process for pi05 + online PPO (with value head).

Required options for learner/actor:
  --config-path PATH      RL config json path for actor/learner/env settings.
  --output-dir PATH       Shared output dir used by learner and actor.

Common options:
  --dataset-root PATH     Offline dataset root (used as warm-start replay source).
  --dataset-repo-id ID    Dataset repo id override. Default: basename(dataset-root).
  --policy-pretrained-path PATH
                          PI05 pretrained path (HF repo or local pretrained_model dir).
  --hf-home PATH          Shared HF cache root (for deterministic local cache).
  --no-persistent-hf-home Disable custom HF_HOME for this run.
  --offline_pretrain_load Force HF/transformers/datasets offline mode.
  --online                Disable offline mode (default behavior).
  --device DEV            policy.device. Default: cuda
  --storage-device DEV    policy.storage_device. Default: cpu
  --online-steps N        policy.online_steps. Default: 300000
  --online-step-before-learning N
                          policy.online_step_before_learning. Default: 2000
  --batch-size N          learner batch size. Default: 128
  --save-freq N           checkpoint freq. Default: 5000
  --log-freq N            log freq. Default: 20
  --resume BOOL           true/false. Default: false
  --wandb-enable BOOL     true/false. Default: false
  --wandb-api-key KEY     Set WANDB_API_KEY for this run (optional).
  --wandb-project NAME    Set wandb.project for this run (optional).
  --run-name NAME         job_name override. Default: basename(output-dir)

PPO/value-head options:
  --actor-lr F            policy.online_rl.actor_lr. Default: 1e-4
  --critic-lr F           policy.online_rl.critic_lr. Default: 1e-4
  --mini-batch-size N     policy.online_rl.mini_batch_size. Default: 128
  --update-epochs N       policy.online_rl.update_epochs. Default: 4
  --clip-ratio F          policy.online_rl.clip_ratio. Default: 0.2
  --value-coef F          policy.online_rl.value_coef. Default: 0.5
  --entropy-coef F        policy.online_rl.entropy_coef. Default: 0.01
  --gamma F               policy.online_rl.gamma. Default: 0.99
  --gae-lambda F          policy.online_rl.gae_lambda. Default: 0.95
  --initial-log-std F     policy.online_rl.initial_log_std. Default: -0.5
  --policy-push-freq N    policy.actor_learner_config.policy_parameters_push_frequency. Default: 4

Network/proxy options:
  --proxy                 Enable default http/https proxy.
  --http-proxy URL        Custom http proxy.
  --https-proxy URL       Custom https proxy.

Examples:
  # 1) learner 终端
  bash scripts/training/trainpi05_online_rl.sh learner \
    --config-path /path/to/train_config_hilserl_so100.json \
    --output-dir /media/jushen/stone-shi/checkpoints/lerobotpi06/2026-05-12_pi05_online_rl \
    --dataset-root /media/jushen/stone-shi/lerobot_v30/put_the_phone_stand_into_the_shipping_box0509_2208 \
    --policy-pretrained-path /media/jushen/stone-shi/checkpoints/lerobotpi06/xxxx/checkpoints/005000/pretrained_model

  # 2) actor 终端（output-dir、config-path 与 learner 保持一致）
  bash scripts/training/trainpi05_online_rl.sh actor \
    --config-path /path/to/train_config_hilserl_so100.json \
    --output-dir /media/jushen/stone-shi/checkpoints/lerobotpi06/2026-05-12_pi05_online_rl \
    --dataset-root /media/jushen/stone-shi/lerobot_v30/put_the_phone_stand_into_the_shipping_box0509_2208 \
    --policy-pretrained-path /media/jushen/stone-shi/checkpoints/lerobotpi06/xxxx/checkpoints/005000/pretrained_model
EOF
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_err() {
  printf '[ERR] %s\n' "$*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENV_PYTHON_BIN="${PROJECT_ROOT}/.venv/bin/python"
PYTHON_BIN="${VENV_PYTHON_BIN}"

ACTION="${1:-}"
if [[ -z "${ACTION}" || "${ACTION}" == "-h" || "${ACTION}" == "--help" || "${ACTION}" == "help" ]]; then
  usage
  exit 0
fi
shift || true

CONFIG_PATH=""
OUTPUT_DIR=""
RUN_NAME=""

DATASET_ROOT="/media/jushen/stone-shi/lerobot_v30/put_the_phone_stand_into_the_shipping_box0509_2208"
DATASET_REPO_ID=""
POLICY_PRETRAINED_PATH="lerobot/pi05_base"

DEVICE="cuda"
STORAGE_DEVICE="cpu"

ONLINE_STEPS="300000"
ONLINE_STEP_BEFORE_LEARNING="2000"
BATCH_SIZE="128"
SAVE_FREQ="5000"
LOG_FREQ="20"
RESUME="false"
WANDB_ENABLE="false"
WANDB_API_KEY_VALUE=""
WANDB_PROJECT_VALUE="${WANDB_PROJECT:-}"
ENABLE_PERSISTENT_HF_HOME="false"
HF_HOME_VALUE="/media/jushen/stone-shi/hf_home"
ENABLE_OFFLINE="false"

ACTOR_LR="1e-4"
CRITIC_LR="1e-4"
MINI_BATCH_SIZE="128"
UPDATE_EPOCHS="4"
CLIP_RATIO="0.2"
VALUE_COEF="0.5"
ENTROPY_COEF="0.01"
GAMMA="0.99"
GAE_LAMBDA="0.95"
INITIAL_LOG_STD="-0.5"
POLICY_PUSH_FREQ="4"

ENABLE_PROXY="false"
HTTP_PROXY_VALUE="http://192.168.32.28:18000"
HTTPS_PROXY_VALUE="http://192.168.32.28:18000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-path)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --run-name)
      RUN_NAME="$2"
      shift 2
      ;;
    --dataset-root)
      DATASET_ROOT="$2"
      shift 2
      ;;
    --dataset-repo-id)
      DATASET_REPO_ID="$2"
      shift 2
      ;;
    --policy-pretrained-path)
      POLICY_PRETRAINED_PATH="$2"
      shift 2
      ;;
    --hf-home)
      HF_HOME_VALUE="$2"
      ENABLE_PERSISTENT_HF_HOME="true"
      shift 2
      ;;
    --no-persistent-hf-home)
      ENABLE_PERSISTENT_HF_HOME="false"
      shift
      ;;
    --offline_pretrain_load)
      ENABLE_OFFLINE="true"
      shift
      ;;
    --offline)
      ENABLE_OFFLINE="true"
      log_info "'--offline' 已废弃，请改用 '--offline_pretrain_load'."
      shift
      ;;
    --online)
      ENABLE_OFFLINE="false"
      shift
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --storage-device)
      STORAGE_DEVICE="$2"
      shift 2
      ;;
    --online-steps)
      ONLINE_STEPS="$2"
      shift 2
      ;;
    --online-step-before-learning)
      ONLINE_STEP_BEFORE_LEARNING="$2"
      shift 2
      ;;
    --batch-size)
      BATCH_SIZE="$2"
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
    --resume)
      RESUME="$2"
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
      WANDB_PROJECT_VALUE="$2"
      shift 2
      ;;
    --actor-lr)
      ACTOR_LR="$2"
      shift 2
      ;;
    --critic-lr)
      CRITIC_LR="$2"
      shift 2
      ;;
    --mini-batch-size)
      MINI_BATCH_SIZE="$2"
      shift 2
      ;;
    --update-epochs)
      UPDATE_EPOCHS="$2"
      shift 2
      ;;
    --clip-ratio)
      CLIP_RATIO="$2"
      shift 2
      ;;
    --value-coef)
      VALUE_COEF="$2"
      shift 2
      ;;
    --entropy-coef)
      ENTROPY_COEF="$2"
      shift 2
      ;;
    --gamma)
      GAMMA="$2"
      shift 2
      ;;
    --gae-lambda)
      GAE_LAMBDA="$2"
      shift 2
      ;;
    --initial-log-std)
      INITIAL_LOG_STD="$2"
      shift 2
      ;;
    --policy-push-freq)
      POLICY_PUSH_FREQ="$2"
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

apply_wandb_env_if_needed() {
  if [[ -n "${WANDB_API_KEY_VALUE}" ]]; then
    export WANDB_API_KEY="${WANDB_API_KEY_VALUE}"
    log_info "WANDB_API_KEY loaded from --wandb-api-key"
  elif [[ -n "${WANDB_API_KEY:-}" ]]; then
    log_info "WANDB_API_KEY detected from environment"
  fi
  if [[ -n "${WANDB_PROJECT_VALUE}" ]]; then
    log_info "WANDB project set to '${WANDB_PROJECT_VALUE}'"
  fi
}

normalize_boolean_flags() {
  RESUME="${RESUME,,}"
  if [[ "${RESUME}" != "true" && "${RESUME}" != "false" ]]; then
    log_err "--resume 仅支持 true/false，收到: ${RESUME}"
    exit 2
  fi

  WANDB_ENABLE="${WANDB_ENABLE,,}"
  if [[ "${WANDB_ENABLE}" != "true" && "${WANDB_ENABLE}" != "false" ]]; then
    log_err "--wandb-enable 仅支持 true/false，收到: ${WANDB_ENABLE}"
    exit 2
  fi
}

require_common_runtime() {
  resolve_runtime_python
  if [[ ! -x "${PYTHON_BIN}" ]]; then
    log_err "${PYTHON_BIN} 不存在或不可执行。请先激活 conda 环境或准备 .venv。"
    exit 1
  fi
}

resolve_runtime_python() {
  local py_candidate=""
  if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/python" ]] && "${CONDA_PREFIX}/bin/python" -V >/dev/null 2>&1; then
    py_candidate="${CONDA_PREFIX}/bin/python"
    log_info "use conda python=${py_candidate}"
  elif [[ -x "${VENV_PYTHON_BIN}" ]] && "${VENV_PYTHON_BIN}" -V >/dev/null 2>&1; then
    py_candidate="${VENV_PYTHON_BIN}"
  elif command -v python >/dev/null 2>&1; then
    py_candidate="$(command -v python)"
    log_info "fallback python=${py_candidate} (.venv/bin/python 不可用)"
  elif command -v python3 >/dev/null 2>&1; then
    py_candidate="$(command -v python3)"
    log_info "fallback python3=${py_candidate} (.venv/bin/python 不可用)"
  else
    log_err "未找到可用 python。请激活 conda 环境（例如 lerobotpi6）或准备 .venv。"
    exit 1
  fi
  PYTHON_BIN="${py_candidate}"
}

require_train_args() {
  if [[ -z "${CONFIG_PATH}" ]]; then
    log_err "--config-path 必填。"
    exit 2
  fi
  if [[ -z "${OUTPUT_DIR}" ]]; then
    log_err "--output-dir 必填（learner 与 actor 必须一致）。"
    exit 2
  fi
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    log_err "config_path 不存在: ${CONFIG_PATH}"
    exit 1
  fi
  if [[ ! -d "${DATASET_ROOT}" ]]; then
    log_err "dataset_root 不存在: ${DATASET_ROOT}"
    exit 1
  fi
  if [[ -z "${DATASET_REPO_ID}" ]]; then
    DATASET_REPO_ID="$(basename "${DATASET_ROOT}")"
  fi
  if [[ -z "${RUN_NAME}" ]]; then
    RUN_NAME="$(basename "${OUTPUT_DIR}")"
  fi
}

build_common_overrides() {
  COMMON_OVERRIDES=(
    "--output_dir=${OUTPUT_DIR}"
    "--job_name=${RUN_NAME}"
    "--dataset.root=${DATASET_ROOT}"
    "--dataset.repo_id=${DATASET_REPO_ID}"
    "--policy.type=pi05"
    "--policy.pretrained_path=${POLICY_PRETRAINED_PATH}"
    "--policy.device=${DEVICE}"
    "--policy.storage_device=${STORAGE_DEVICE}"
    "--policy.online_steps=${ONLINE_STEPS}"
    "--policy.online_step_before_learning=${ONLINE_STEP_BEFORE_LEARNING}"
    "--policy.actor_learner_config.policy_parameters_push_frequency=${POLICY_PUSH_FREQ}"
    "--policy.online_rl.enabled=true"
    "--policy.online_rl.algorithm=ppo"
    "--policy.online_rl.actor_lr=${ACTOR_LR}"
    "--policy.online_rl.critic_lr=${CRITIC_LR}"
    "--policy.online_rl.gamma=${GAMMA}"
    "--policy.online_rl.gae_lambda=${GAE_LAMBDA}"
    "--policy.online_rl.clip_ratio=${CLIP_RATIO}"
    "--policy.online_rl.value_coef=${VALUE_COEF}"
    "--policy.online_rl.entropy_coef=${ENTROPY_COEF}"
    "--policy.online_rl.update_epochs=${UPDATE_EPOCHS}"
    "--policy.online_rl.mini_batch_size=${MINI_BATCH_SIZE}"
    "--policy.online_rl.initial_log_std=${INITIAL_LOG_STD}"
    "--batch_size=${BATCH_SIZE}"
    "--save_freq=${SAVE_FREQ}"
    "--log_freq=${LOG_FREQ}"
    "--resume=${RESUME}"
    "--wandb.enable=${WANDB_ENABLE}"
  )
  if [[ -n "${WANDB_PROJECT_VALUE}" ]]; then
    COMMON_OVERRIDES+=("--wandb.project=${WANDB_PROJECT_VALUE}")
  fi
}

run_check() {
  cd "${PROJECT_ROOT}"
  apply_proxy_if_needed
  apply_hf_home_if_needed
  apply_offline_if_needed
  require_common_runtime
  log_info "python=${PYTHON_BIN}"
  "${PYTHON_BIN}" -V
  "${PYTHON_BIN}" - <<'PY'
import importlib
import sys

checks = (
    "lerobot.policies.pi05.configuration_pi05",
    "lerobot.policies.pi05.modeling_pi05",
    "grpc",
)
missing = []
for name in checks:
    try:
        importlib.import_module(name)
    except Exception as exc:
        missing.append((name, repr(exc)))

if missing:
    print("[ERR] onlineRL 运行依赖不完整：")
    for name, err in missing:
        print(f"  - {name}: {err}")
    print("[HINT] 请在目标环境安装：pip install -e '.[pi,grpcio-dep]' --no-build-isolation")
    sys.exit(1)

print("[INFO] pi05 + onlineRL 关键依赖检查通过。")
PY
}

run_learner() {
  cd "${PROJECT_ROOT}"
  apply_proxy_if_needed
  apply_hf_home_if_needed
  apply_offline_if_needed
  require_common_runtime
  require_train_args
  normalize_boolean_flags
  apply_wandb_env_if_needed
  build_common_overrides

  if [[ "${RESUME}" != "true" && -d "${OUTPUT_DIR}" ]] && [[ -n "$(ls -A "${OUTPUT_DIR}")" ]]; then
    log_err "输出目录非空，已停止以避免覆盖: ${OUTPUT_DIR}"
    log_err "如需续训请显式加 --resume true，并确认配置一致。"
    exit 1
  fi

  mkdir -p "${OUTPUT_DIR}"
  log_info "config_path=${CONFIG_PATH}"
  log_info "output_dir=${OUTPUT_DIR}"
  log_info "dataset_root=${DATASET_ROOT}"
  log_info "policy_pretrained_path=${POLICY_PRETRAINED_PATH}"
  log_info "device=${DEVICE}, storage_device=${STORAGE_DEVICE}"
  log_info "wandb_enable=${WANDB_ENABLE}"
  if [[ -n "${WANDB_PROJECT_VALUE}" ]]; then
    log_info "wandb_project=${WANDB_PROJECT_VALUE}"
  fi

  PYTHONPATH=src "${PYTHON_BIN}" -m lerobot.rl.learner \
    "--config_path=${CONFIG_PATH}" \
    "${COMMON_OVERRIDES[@]}"
}

run_actor() {
  cd "${PROJECT_ROOT}"
  apply_proxy_if_needed
  apply_hf_home_if_needed
  apply_offline_if_needed
  require_common_runtime
  require_train_args
  normalize_boolean_flags
  apply_wandb_env_if_needed
  build_common_overrides

  mkdir -p "${OUTPUT_DIR}"
  log_info "config_path=${CONFIG_PATH}"
  log_info "output_dir=${OUTPUT_DIR}"
  log_info "dataset_root=${DATASET_ROOT}"
  log_info "policy_pretrained_path=${POLICY_PRETRAINED_PATH}"
  log_info "device=${DEVICE}, storage_device=${STORAGE_DEVICE}"
  log_info "wandb_enable=${WANDB_ENABLE}"
  if [[ -n "${WANDB_PROJECT_VALUE}" ]]; then
    log_info "wandb_project=${WANDB_PROJECT_VALUE}"
  fi

  PYTHONPATH=src "${PYTHON_BIN}" -m lerobot.rl.actor \
    "--config_path=${CONFIG_PATH}" \
    "${COMMON_OVERRIDES[@]}"
}

case "${ACTION}" in
  check)
    run_check
    ;;
  learner)
    run_learner
    ;;
  actor)
    run_actor
    ;;
  *)
    log_err "Unknown command: ${ACTION}"
    usage
    exit 2
    ;;
esac
