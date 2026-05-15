#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/training/env_trainpi05.sh <command> [options] [passthrough args...]

Commands:
  init       One-time prepare shared venv/hf-home/pretrained model.
  link       Link project .venv to shared venv (safe mode).
  check      Auto init/link if needed, then run trainpi05.sh check.
  smoke      Auto init/link if needed, then run trainpi05.sh smoke.
  train      Auto init/link if needed, then run trainpi05.sh train.
  train-only Skip init, run link+validate, then run trainpi05.sh train.
  online-check    Auto init/link if needed, then run trainpi05_online_rl.sh check.
  online-learner  Auto init/link if needed, then run trainpi05_online_rl.sh learner.
  online-actor    Auto init/link if needed, then run trainpi05_online_rl.sh actor.
  bootstrap  Run init + link + check in one command.

Common options:
  --project-root PATH      Project root. Default: auto-detect from this script.
  --shared-root PATH       Shared root. Default: /media/jushen/stone-shi
  --shared-venv PATH       Shared venv path.
  --shared-hf-home PATH    Shared HF_HOME path.
  --shared-model-dir PATH  Shared local pretrained model directory.
  --shared-tokenizer-dir PATH
                           Shared local tokenizer directory for offline tokenizer loading.
  --model-repo-id ID       HF repo id to download. Default: lerobot/pi05_base
  --tokenizer-repo-id ID   HF tokenizer repo id. Default: google/paligemma-3b-pt-224
  --wait-timeout-sec N     Wait timeout for shared runtime ready. Default: 1800
  --lock-warn-interval-sec N
                           Print lock wait diagnostics every N seconds. Default: 30
  --lock-heartbeat-sec N   Lock heartbeat write interval seconds. Default: 10
  --lock-stale-sec N       Consider lock stale if heartbeat older than N seconds. Default: 120
  --auto-clean-zombie-lock
                           Auto-clean stale lock directory when safe to verify.
  --no-zombie-lock-prompt  Disable interactive prompt for stale lock cleanup.
  --proxy                  Enable proxy env export.
  --http-proxy URL         Override http proxy.
  --https-proxy URL        Override https proxy.
  --hf-token TOKEN         HF token used by init login/download.
  --force-link             Replace existing project .venv with symlink.
  --skip-init-env
  --skipinitenv            Skip run_init in train/check/smoke/online-*,
                           keep link+validate only. Use when shared runtime
                           is already prepared and healthy.

Init-only options:
  --refresh-venv           Rebuild shared venv from scratch.
  --refresh-model          Re-download pretrained model snapshot.
  --refresh-tokenizer      Re-download tokenizer assets.
  --skip-model-download    Skip pretrained model download in init.
  --skip-tokenizer-download
                           Skip tokenizer assets download in init.
  --skip-login             Skip hf auth login in init.

Notes:
  - For train/smoke/check, unknown args are passed through to trainpi05.sh.
  - For online-check/online-learner/online-actor, unknown args are passed through to trainpi05_online_rl.sh.
  - online-* 默认使用隔离 shared-root: /media/jushen/stone-shi/lerobot_pi05online_rl_runtime
  - Defaults added by this wrapper: --hf-home <shared-hf-home>, --pretrained-path <shared-model-dir>, --offline_pretrain_load.
  - Online commands also add: --policy-pretrained-path <shared-model-dir>, --hf-home <shared-hf-home>, --offline_pretrain_load.
  - init rewrites tokenizer refs in policy_preprocessor.json to local tokenizer directory.
  - If a stale lock is detected, the script can prompt or auto-clean safely.
  - Pass --online in trailing args if you explicitly need online mode.
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
PROJECT_ROOT_DEFAULT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ACTION="${1:-}"
if [[ -z "${ACTION}" || "${ACTION}" == "-h" || "${ACTION}" == "--help" || "${ACTION}" == "help" ]]; then
  usage
  exit 0
fi
shift || true

PROJECT_ROOT="${PROJECT_ROOT_DEFAULT}"
SHARED_ROOT="/media/jushen/stone-shi"
SHARED_ROOT_OVERRIDDEN="false"
SHARED_VENV=""
SHARED_HF_HOME=""
SHARED_MODEL_DIR=""
SHARED_TOKENIZER_DIR=""
MODEL_REPO_ID="lerobot/pi05_base"
TOKENIZER_REPO_ID="google/paligemma-3b-pt-224"
WAIT_TIMEOUT_SEC="1800"
LOCK_WARN_INTERVAL_SEC="30"
LOCK_HEARTBEAT_SEC="10"
LOCK_STALE_SEC="120"

ENABLE_PROXY="false"
HTTP_PROXY_VALUE="http://192.168.32.28:18000"
HTTPS_PROXY_VALUE="http://192.168.32.28:18000"
HF_TOKEN=""

FORCE_LINK="false"
SKIP_INIT_ENV="false"
REFRESH_VENV="false"
REFRESH_MODEL="false"
REFRESH_TOKENIZER="false"
SKIP_MODEL_DOWNLOAD="false"
SKIP_TOKENIZER_DOWNLOAD="false"
SKIP_LOGIN="false"
AUTO_CLEAN_ZOMBIE_LOCK="false"
PROMPT_CLEAN_ZOMBIE_LOCK="true"

EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --shared-root)
      SHARED_ROOT="$2"
      SHARED_ROOT_OVERRIDDEN="true"
      shift 2
      ;;
    --shared-venv)
      SHARED_VENV="$2"
      shift 2
      ;;
    --shared-hf-home)
      SHARED_HF_HOME="$2"
      shift 2
      ;;
    --shared-model-dir)
      SHARED_MODEL_DIR="$2"
      shift 2
      ;;
    --shared-tokenizer-dir)
      SHARED_TOKENIZER_DIR="$2"
      shift 2
      ;;
    --model-repo-id)
      MODEL_REPO_ID="$2"
      shift 2
      ;;
    --tokenizer-repo-id)
      TOKENIZER_REPO_ID="$2"
      shift 2
      ;;
    --wait-timeout-sec)
      WAIT_TIMEOUT_SEC="$2"
      shift 2
      ;;
    --lock-warn-interval-sec)
      LOCK_WARN_INTERVAL_SEC="$2"
      shift 2
      ;;
    --lock-heartbeat-sec)
      LOCK_HEARTBEAT_SEC="$2"
      shift 2
      ;;
    --lock-stale-sec)
      LOCK_STALE_SEC="$2"
      shift 2
      ;;
    --auto-clean-zombie-lock)
      AUTO_CLEAN_ZOMBIE_LOCK="true"
      shift
      ;;
    --no-zombie-lock-prompt)
      PROMPT_CLEAN_ZOMBIE_LOCK="false"
      shift
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
    --hf-token)
      HF_TOKEN="$2"
      shift 2
      ;;
    --force-link)
      FORCE_LINK="true"
      shift
      ;;
    --skip-init-env|--skip-initenv|--skip-initenv)
      SKIP_INIT_ENV="true"
      shift
      ;;
    --refresh-venv)
      REFRESH_VENV="true"
      shift
      ;;
    --refresh-model)
      REFRESH_MODEL="true"
      shift
      ;;
    --refresh-tokenizer)
      REFRESH_TOKENIZER="true"
      shift
      ;;
    --skip-model-download)
      SKIP_MODEL_DOWNLOAD="true"
      shift
      ;;
    --skip-tokenizer-download)
      SKIP_TOKENIZER_DOWNLOAD="true"
      shift
      ;;
    --skip-login)
      SKIP_LOGIN="true"
      shift
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

IS_ONLINE_RL_ACTION="false"
case "${ACTION}" in
  online-check|online-learner|online-actor)
    IS_ONLINE_RL_ACTION="true"
    ;;
esac

if [[ "${IS_ONLINE_RL_ACTION}" == "true" && "${SHARED_ROOT_OVERRIDDEN}" != "true" ]]; then
  SHARED_ROOT="${SHARED_ROOT}/lerobot_pi05online_rl_runtime"
fi

if [[ -z "${SHARED_VENV}" ]]; then
  if [[ "${IS_ONLINE_RL_ACTION}" == "true" ]]; then
    SHARED_VENV="${SHARED_ROOT}/runtime/venv_pi05online_rl_py310"
  else
    SHARED_VENV="${SHARED_ROOT}/runtime/lerobot_pi06/venv_pi05_py310"
  fi
fi
if [[ -z "${SHARED_HF_HOME}" ]]; then
  SHARED_HF_HOME="${SHARED_ROOT}/hf_home"
fi
if [[ -z "${SHARED_MODEL_DIR}" ]]; then
  SHARED_MODEL_DIR="${SHARED_ROOT}/models/lerobot_pi05_base"
fi
if [[ -z "${SHARED_TOKENIZER_DIR}" ]]; then
  SHARED_TOKENIZER_DIR="${SHARED_ROOT}/models/google_paligemma_3b_pt_224_tokenizer"
fi

SHARED_RUNTIME_DIR="$(dirname "${SHARED_VENV}")"
READY_FILE="${SHARED_RUNTIME_DIR}/.shared_runtime_ready"
LOCK_DIR="${SHARED_RUNTIME_DIR}/.shared_runtime_lock"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.env"
LOCK_HEARTBEAT_FILE="${LOCK_DIR}/heartbeat"
TRAINPI05_SH="${PROJECT_ROOT}/scripts/training/trainpi05.sh"
TRAINPI05_ONLINE_RL_SH="${PROJECT_ROOT}/scripts/training/trainpi05_online_rl.sh"
CURRENT_HOST="$(hostname 2>/dev/null || echo unknown-host)"
LOCK_ACQUIRED_BY_ME="false"
LOCK_PROMPT_DONE="false"
LOCK_HEARTBEAT_PID=""
LOCK_META_PID=""
LOCK_META_HOST=""
LOCK_META_ACTION=""
LOCK_META_CREATED_AT=""
LOCK_META_SCRIPT=""
LOCK_ZOMBIE_CONFIDENCE="none"
LOCK_ZOMBIE_REASON=""

if [[ ! -f "${TRAINPI05_SH}" ]]; then
  log_err "trainpi05.sh not found: ${TRAINPI05_SH}"
  exit 1
fi
if [[ "${IS_ONLINE_RL_ACTION}" == "true" && ! -f "${TRAINPI05_ONLINE_RL_SH}" ]]; then
  log_err "trainpi05_online_rl.sh not found: ${TRAINPI05_ONLINE_RL_SH}"
  exit 1
fi

if [[ ("${ACTION}" == "init" || "${ACTION}" == "link") && "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
  log_err "Unknown extra args for '${ACTION}': ${EXTRA_ARGS[*]}"
  exit 2
fi

apply_proxy_if_needed() {
  if [[ "${ENABLE_PROXY}" == "true" ]]; then
    export http_proxy="${HTTP_PROXY_VALUE}"
    export https_proxy="${HTTPS_PROXY_VALUE}"
    log_info "http_proxy=${http_proxy}"
    log_info "https_proxy=${https_proxy}"
  fi
}

apply_shared_hf_env() {
  mkdir -p "${SHARED_HF_HOME}"
  export HF_HOME="${SHARED_HF_HOME}"
  export HUGGINGFACE_HUB_CACHE="${HF_HOME}/hub"
  export HF_HUB_CACHE="${HUGGINGFACE_HUB_CACHE}"
  export HF_DATASETS_CACHE="${HF_HOME}/datasets"
  log_info "HF_HOME=${HF_HOME}"
  log_info "HUGGINGFACE_HUB_CACHE=${HUGGINGFACE_HUB_CACHE}"
}

safe_file_mtime_epoch() {
  local target="$1"
  if [[ ! -e "${target}" ]]; then
    return 1
  fi

  local mtime
  mtime="$(stat -c %Y "${target}" 2>/dev/null || true)"
  if [[ -z "${mtime}" ]]; then
    mtime="$(stat -f %m "${target}" 2>/dev/null || true)"
  fi
  if [[ -z "${mtime}" ]]; then
    return 1
  fi
  printf '%s\n' "${mtime}"
}

lock_heartbeat_age_sec() {
  local now_epoch
  local hb_epoch
  now_epoch="$(date +%s)"
  hb_epoch="$(safe_file_mtime_epoch "${LOCK_HEARTBEAT_FILE}" 2>/dev/null || true)"
  if [[ -z "${hb_epoch}" ]]; then
    return 1
  fi
  printf '%s\n' "$((now_epoch - hb_epoch))"
}

read_lock_owner_metadata() {
  LOCK_META_PID=""
  LOCK_META_HOST=""
  LOCK_META_ACTION=""
  LOCK_META_CREATED_AT=""
  LOCK_META_SCRIPT=""
  if [[ ! -f "${LOCK_OWNER_FILE}" ]]; then
    return 1
  fi

  local line
  local key
  local value
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    case "${key}" in
      pid)
        LOCK_META_PID="${value}"
        ;;
      host)
        LOCK_META_HOST="${value}"
        ;;
      action)
        LOCK_META_ACTION="${value}"
        ;;
      created_at)
        LOCK_META_CREATED_AT="${value}"
        ;;
      script)
        LOCK_META_SCRIPT="${value}"
        ;;
    esac
  done < "${LOCK_OWNER_FILE}"

  return 0
}

describe_lock_owner() {
  local hb_age="unknown"
  local hb_age_value
  hb_age_value="$(lock_heartbeat_age_sec 2>/dev/null || true)"
  if [[ -n "${hb_age_value}" ]]; then
    hb_age="${hb_age_value}s"
  fi

  if read_lock_owner_metadata; then
    printf 'pid=%s host=%s action=%s created_at=%s script=%s heartbeat_age=%s' \
      "${LOCK_META_PID:-unknown}" \
      "${LOCK_META_HOST:-unknown}" \
      "${LOCK_META_ACTION:-unknown}" \
      "${LOCK_META_CREATED_AT:-unknown}" \
      "${LOCK_META_SCRIPT:-unknown}" \
      "${hb_age}"
    return 0
  fi
  printf 'metadata=missing heartbeat_age=%s' "${hb_age}"
}

write_lock_owner_metadata() {
  cat > "${LOCK_OWNER_FILE}" <<EOF
pid=$$
host=${CURRENT_HOST}
action=${ACTION}
created_at=$(date -Iseconds)
script=${BASH_SOURCE[0]}
project_root=${PROJECT_ROOT}
EOF
  printf '%s\n' "$(date +%s)" > "${LOCK_HEARTBEAT_FILE}"
}

start_lock_heartbeat() {
  if [[ "${LOCK_HEARTBEAT_SEC}" -lt 1 ]]; then
    LOCK_HEARTBEAT_SEC="10"
  fi
  if [[ ! -d "${LOCK_DIR}" ]]; then
    return 0
  fi
  (
    while [[ -d "${LOCK_DIR}" ]]; do
      printf '%s\n' "$(date +%s)" > "${LOCK_HEARTBEAT_FILE}" 2>/dev/null || true
      sleep "${LOCK_HEARTBEAT_SEC}"
    done
  ) &
  LOCK_HEARTBEAT_PID="$!"
}

stop_lock_heartbeat() {
  if [[ -n "${LOCK_HEARTBEAT_PID}" ]]; then
    kill "${LOCK_HEARTBEAT_PID}" >/dev/null 2>&1 || true
    wait "${LOCK_HEARTBEAT_PID}" 2>/dev/null || true
    LOCK_HEARTBEAT_PID=""
  fi
}

release_lock() {
  if [[ "${LOCK_ACQUIRED_BY_ME}" != "true" ]]; then
    return 0
  fi
  stop_lock_heartbeat
  rm -f "${LOCK_OWNER_FILE}" >/dev/null 2>&1 || true
  rm -f "${LOCK_HEARTBEAT_FILE}" >/dev/null 2>&1 || true
  rmdir "${LOCK_DIR}" >/dev/null 2>&1 || true
  LOCK_ACQUIRED_BY_ME="false"
}

cleanup_stale_lock_dir() {
  local reason="$1"
  if [[ ! -d "${LOCK_DIR}" ]]; then
    return 0
  fi

  log_warn "Trying to cleanup stale lock: ${LOCK_DIR} (reason: ${reason})"
  rm -f "${LOCK_OWNER_FILE}" >/dev/null 2>&1 || true
  rm -f "${LOCK_HEARTBEAT_FILE}" >/dev/null 2>&1 || true
  if rmdir "${LOCK_DIR}" >/dev/null 2>&1; then
    log_info "Stale lock removed: ${LOCK_DIR}"
    LOCK_PROMPT_DONE="false"
    return 0
  fi

  local remaining_entries
  remaining_entries="$(ls -A "${LOCK_DIR}" 2>/dev/null || true)"
  if [[ -n "${remaining_entries}" ]]; then
    log_warn "Lock dir not empty, skip cleanup for safety. Remaining entries: ${remaining_entries}"
  else
    log_warn "Failed to remove lock dir: ${LOCK_DIR}"
  fi
  return 1
}

detect_zombie_lock_candidate() {
  LOCK_ZOMBIE_CONFIDENCE="none"
  LOCK_ZOMBIE_REASON=""
  if [[ ! -d "${LOCK_DIR}" ]]; then
    return 1
  fi

  local hb_age
  hb_age="$(lock_heartbeat_age_sec 2>/dev/null || true)"
  if [[ -n "${hb_age}" ]]; then
    if (( hb_age > LOCK_STALE_SEC )); then
      LOCK_ZOMBIE_CONFIDENCE="high"
      LOCK_ZOMBIE_REASON="lock heartbeat is stale (${hb_age}s > ${LOCK_STALE_SEC}s)"
      return 0
    fi
    return 1
  fi

  if read_lock_owner_metadata; then
    if [[ -z "${LOCK_META_PID}" || -z "${LOCK_META_HOST}" ]]; then
      LOCK_ZOMBIE_CONFIDENCE="low"
      LOCK_ZOMBIE_REASON="owner metadata incomplete"
      return 0
    fi

    if [[ "${LOCK_META_HOST}" != "${CURRENT_HOST}" ]]; then
      return 1
    fi

    if [[ "${LOCK_META_PID}" =~ ^[0-9]+$ ]] && kill -0 "${LOCK_META_PID}" 2>/dev/null; then
      return 1
    fi

    LOCK_ZOMBIE_CONFIDENCE="high"
    LOCK_ZOMBIE_REASON="owner pid ${LOCK_META_PID} is not alive on host ${CURRENT_HOST}"
    return 0
  fi

  local lock_age
  lock_age="$(safe_file_mtime_epoch "${LOCK_DIR}" 2>/dev/null || true)"
  if [[ -n "${lock_age}" ]]; then
    local now_epoch
    now_epoch="$(date +%s)"
    lock_age="$((now_epoch - lock_age))"
    if (( lock_age > LOCK_STALE_SEC )); then
      LOCK_ZOMBIE_CONFIDENCE="low"
      LOCK_ZOMBIE_REASON="owner metadata/heartbeat missing and lock age is ${lock_age}s"
      return 0
    fi
  fi

  LOCK_ZOMBIE_CONFIDENCE="none"
  LOCK_ZOMBIE_REASON=""
  return 0
}

maybe_recover_stale_lock() {
  if ! detect_zombie_lock_candidate; then
    return 1
  fi

  if [[ "${LOCK_ZOMBIE_CONFIDENCE}" == "none" ]]; then
    return 1
  fi

  if [[ "${AUTO_CLEAN_ZOMBIE_LOCK}" == "true" ]]; then
    if [[ "${LOCK_ZOMBIE_CONFIDENCE}" == "high" ]]; then
      cleanup_stale_lock_dir "${LOCK_ZOMBIE_REASON}" && return 0
      return 1
    fi
    log_warn "Low-confidence stale lock detected but skip auto-clean for safety: ${LOCK_ZOMBIE_REASON}"
    return 1
  fi

  if [[ "${PROMPT_CLEAN_ZOMBIE_LOCK}" != "true" ]]; then
    # In non-interactive container startup, high-confidence stale lock can be cleaned safely.
    if [[ ! -t 0 && "${LOCK_ZOMBIE_CONFIDENCE}" == "high" ]]; then
      cleanup_stale_lock_dir "${LOCK_ZOMBIE_REASON}" && return 0
    fi
    return 1
  fi

  if [[ "${LOCK_PROMPT_DONE}" == "true" ]]; then
    return 1
  fi

  log_warn "Detected potential stale lock (${LOCK_ZOMBIE_CONFIDENCE} confidence): ${LOCK_ZOMBIE_REASON}"
  log_warn "Lock owner info: $(describe_lock_owner)"
  if [[ ! -t 0 ]]; then
    if [[ "${LOCK_ZOMBIE_CONFIDENCE}" == "high" ]]; then
      cleanup_stale_lock_dir "${LOCK_ZOMBIE_REASON}" && return 0
    fi
    log_warn "No interactive TTY for prompt. Use --auto-clean-zombie-lock if you want automatic cleanup."
    LOCK_PROMPT_DONE="true"
    return 1
  fi

  local answer
  read -r -p "Remove stale lock '${LOCK_DIR}' now? [y/N] " answer
  LOCK_PROMPT_DONE="true"
  case "${answer,,}" in
    y|yes)
      cleanup_stale_lock_dir "${LOCK_ZOMBIE_REASON}" && return 0
      ;;
  esac
  log_warn "Keep waiting for lock. You can rerun with --auto-clean-zombie-lock."
  return 1
}

acquire_lock() {
  mkdir -p "${SHARED_RUNTIME_DIR}"
  local waited=0
  local last_warned_sec=-1
  while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    maybe_recover_stale_lock && continue
    if (( waited >= WAIT_TIMEOUT_SEC )); then
      log_err "Timeout waiting init lock: ${LOCK_DIR} (owner: $(describe_lock_owner))"
      return 1
    fi
    if (( waited == 0 || waited - last_warned_sec >= LOCK_WARN_INTERVAL_SEC )); then
      log_warn "Init lock busy for ${waited}s: ${LOCK_DIR} (owner: $(describe_lock_owner))"
      last_warned_sec="${waited}"
    fi
    sleep 2
    waited=$((waited + 2))
  done
  LOCK_ACQUIRED_BY_ME="true"
  write_lock_owner_metadata
  start_lock_heartbeat
  trap 'release_lock' EXIT INT TERM
}

wait_for_ready() {
  if [[ -f "${READY_FILE}" ]]; then
    return 0
  fi
  log_info "Waiting shared runtime ready marker: ${READY_FILE}"
  local waited=0
  while [[ ! -f "${READY_FILE}" ]]; do
    if (( waited >= WAIT_TIMEOUT_SEC )); then
      log_err "Timeout waiting ready marker. Run init first."
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

ensure_uv() {
  if ! command -v uv >/dev/null 2>&1; then
    log_err "'uv' not found in PATH. Please install uv first."
    return 1
  fi
}

install_shared_python_packages() {
  local shared_python="${SHARED_VENV}/bin/python"
  if [[ ! -x "${shared_python}" ]]; then
    log_err "Shared python not executable: ${shared_python}"
    return 1
  fi

  if ! "${shared_python}" -m pip --version >/dev/null 2>&1; then
    log_warn "pip is missing in shared env, trying ensurepip."
    "${shared_python}" -m ensurepip --upgrade
  fi

  "${shared_python}" -m pip install -U pip setuptools wheel
  "${shared_python}" -m pip install -e ".[pi]"
}

validate_shared_runtime() {
  if [[ ! -x "${SHARED_VENV}/bin/python" ]]; then
    log_err "Shared python not executable: ${SHARED_VENV}/bin/python"
    return 1
  fi
  if [[ ! -x "${SHARED_VENV}/bin/accelerate" ]]; then
    log_err "Shared accelerate missing: ${SHARED_VENV}/bin/accelerate"
    return 1
  fi
  if [[ ! -x "${SHARED_VENV}/bin/hf" ]]; then
    log_err "Shared hf CLI missing: ${SHARED_VENV}/bin/hf"
    return 1
  fi
  if [[ ! -f "${SHARED_MODEL_DIR}/config.json" ]]; then
    log_err "Shared pretrained model config missing: ${SHARED_MODEL_DIR}/config.json"
    return 1
  fi
  if [[ ! -f "${SHARED_TOKENIZER_DIR}/config.json" ]]; then
    log_err "Shared tokenizer config missing: ${SHARED_TOKENIZER_DIR}/config.json"
    return 1
  fi
  if [[ ! -f "${SHARED_TOKENIZER_DIR}/tokenizer_config.json" ]]; then
    log_err "Shared tokenizer metadata missing: ${SHARED_TOKENIZER_DIR}/tokenizer_config.json"
    return 1
  fi

  local preprocessor_cfg="${SHARED_MODEL_DIR}/policy_preprocessor.json"
  if [[ -f "${preprocessor_cfg}" ]]; then
    PREPROCESSOR_CFG_ENV="${preprocessor_cfg}" \
    TOKENIZER_REPO_ID_ENV="${TOKENIZER_REPO_ID}" \
    SHARED_TOKENIZER_DIR_ENV="${SHARED_TOKENIZER_DIR}" \
    "${SHARED_VENV}/bin/python" - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ["PREPROCESSOR_CFG_ENV"])
tokenizer_repo_id = os.environ["TOKENIZER_REPO_ID_ENV"]
local_tokenizer_dir = os.environ["SHARED_TOKENIZER_DIR_ENV"]

data = json.loads(config_path.read_text())
for step in data.get("steps", []):
    cfg = step.get("config")
    if not isinstance(cfg, dict):
        continue
    for key in ("tokenizer_name", "paligemma_tokenizer_name"):
        value = cfg.get(key)
        if value == tokenizer_repo_id:
            raise SystemExit(
                f"Preprocessor still references remote tokenizer '{tokenizer_repo_id}'. "
                f"Please localize it to '{local_tokenizer_dir}'."
            )
PY
  fi
}

prepare_shared_venv() {
  mkdir -p "${SHARED_RUNTIME_DIR}"
  local need_rebuild="false"
  local force_repair="false"
  local is_conda_env="false"
  if [[ -f "${SHARED_VENV}/conda-meta/history" ]]; then
    is_conda_env="true"
  fi

  if [[ "${REFRESH_VENV}" == "true" ]]; then
    if [[ "${is_conda_env}" == "true" ]]; then
      log_warn "--refresh-venv is requested on conda env; skip destructive rebuild and repair packages only."
      force_repair="true"
    else
      need_rebuild="true"
    fi
  elif [[ ! -x "${SHARED_VENV}/bin/python" ]]; then
    need_rebuild="true"
  fi

  cd "${PROJECT_ROOT}"
  if [[ "${need_rebuild}" == "true" ]]; then
    ensure_uv
    log_info "Building shared venv via uv: ${SHARED_VENV}"
    uv python install 3.10
    uv venv --python 3.10 --clear "${SHARED_VENV}"
    install_shared_python_packages
  elif [[ ! -x "${SHARED_VENV}/bin/python" ]]; then
    log_err "Shared python not executable: ${SHARED_VENV}/bin/python"
    return 1
  elif [[ "${force_repair}" == "true" || ! -x "${SHARED_VENV}/bin/accelerate" || ! -x "${SHARED_VENV}/bin/hf" ]]; then
    if [[ "${is_conda_env}" == "true" ]]; then
      log_info "Repairing shared conda env tools in: ${SHARED_VENV}"
    else
      log_info "Repairing shared venv tools in: ${SHARED_VENV}"
    fi
    install_shared_python_packages
  else
    if [[ "${is_conda_env}" == "true" ]]; then
      log_info "Shared conda env already exists: ${SHARED_VENV}"
    else
      log_info "Shared venv already exists: ${SHARED_VENV}"
    fi
  fi

  "${SHARED_VENV}/bin/python" -c "import transformers; from transformers.models.siglip import check; ok=check.check_whether_transformers_replace_is_installed_correctly(); print('transformers:', transformers.__version__); print('siglip patch ok:', ok); raise SystemExit(0 if ok else 1)"
}

maybe_login_hf() {
  if [[ "${SKIP_LOGIN}" == "true" ]]; then
    return 0
  fi
  if [[ -z "${HF_TOKEN}" ]]; then
    log_info "No --hf-token provided, skip hf login."
    return 0
  fi
  "${SHARED_VENV}/bin/hf" auth login --token "${HF_TOKEN}"

  local max_retry=3
  local attempt=1
  local ok="false"
  while [[ "${attempt}" -le "${max_retry}" ]]; do
    if "${SHARED_VENV}/bin/hf" auth whoami; then
      ok="true"
      break
    fi
    log_warn "hf auth whoami failed (attempt ${attempt}/${max_retry}), maybe transient TLS/proxy issue."
    if [[ "${attempt}" -lt "${max_retry}" ]]; then
      sleep 2
    fi
    attempt=$((attempt + 1))
  done
  if [[ "${ok}" != "true" ]]; then
    log_warn "whoami check still failed, but token may already be saved locally."
  fi
}

maybe_download_model() {
  if [[ "${SKIP_MODEL_DOWNLOAD}" == "true" ]]; then
    return 0
  fi
  if [[ "${REFRESH_MODEL}" != "true" && -f "${SHARED_MODEL_DIR}/config.json" ]]; then
    log_info "Shared pretrained model already exists: ${SHARED_MODEL_DIR}"
    return 0
  fi

  mkdir -p "${SHARED_MODEL_DIR}"
  log_info "Downloading pretrained model '${MODEL_REPO_ID}' to ${SHARED_MODEL_DIR}"
  MODEL_REPO_ID_ENV="${MODEL_REPO_ID}" \
  SHARED_MODEL_DIR_ENV="${SHARED_MODEL_DIR}" \
  HF_TOKEN_ENV="${HF_TOKEN}" \
  "${SHARED_VENV}/bin/python" - <<'PY'
import os
from huggingface_hub import snapshot_download

repo_id = os.environ["MODEL_REPO_ID_ENV"]
local_dir = os.environ["SHARED_MODEL_DIR_ENV"]
token = os.environ.get("HF_TOKEN_ENV") or None

snapshot_download(
    repo_id=repo_id,
    local_dir=local_dir,
    local_dir_use_symlinks=False,
    resume_download=True,
    token=token,
)
print(f"snapshot_download done: {local_dir}")
PY
}

maybe_download_tokenizer() {
  if [[ "${SKIP_TOKENIZER_DOWNLOAD}" == "true" ]]; then
    return 0
  fi
  if [[ "${REFRESH_TOKENIZER}" != "true" && -f "${SHARED_TOKENIZER_DIR}/config.json" && -f "${SHARED_TOKENIZER_DIR}/tokenizer_config.json" ]]; then
    log_info "Shared tokenizer already exists: ${SHARED_TOKENIZER_DIR}"
    return 0
  fi

  mkdir -p "${SHARED_TOKENIZER_DIR}"
  log_info "Downloading tokenizer assets '${TOKENIZER_REPO_ID}' to ${SHARED_TOKENIZER_DIR}"
  TOKENIZER_REPO_ID_ENV="${TOKENIZER_REPO_ID}" \
  SHARED_TOKENIZER_DIR_ENV="${SHARED_TOKENIZER_DIR}" \
  HF_TOKEN_ENV="${HF_TOKEN}" \
  "${SHARED_VENV}/bin/python" - <<'PY'
import os
from huggingface_hub import snapshot_download

repo_id = os.environ["TOKENIZER_REPO_ID_ENV"]
local_dir = os.environ["SHARED_TOKENIZER_DIR_ENV"]
token = os.environ.get("HF_TOKEN_ENV") or None

snapshot_download(
    repo_id=repo_id,
    local_dir=local_dir,
    local_dir_use_symlinks=False,
    resume_download=True,
    token=token,
    allow_patterns=[
        "config.json",
        "tokenizer.model",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "added_tokens.json",
        "*.model",
    ],
)
print(f"tokenizer snapshot_download done: {local_dir}")
PY
}

rewrite_preprocessor_tokenizer_paths() {
  local preprocessor_cfg="${SHARED_MODEL_DIR}/policy_preprocessor.json"
  if [[ ! -f "${preprocessor_cfg}" ]]; then
    log_warn "Preprocessor config not found, skip tokenizer localization: ${preprocessor_cfg}"
    return 0
  fi

  PREPROCESSOR_CFG_ENV="${preprocessor_cfg}" \
  TOKENIZER_REPO_ID_ENV="${TOKENIZER_REPO_ID}" \
  SHARED_TOKENIZER_DIR_ENV="${SHARED_TOKENIZER_DIR}" \
  "${SHARED_VENV}/bin/python" - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ["PREPROCESSOR_CFG_ENV"])
tokenizer_repo_id = os.environ["TOKENIZER_REPO_ID_ENV"]
local_tokenizer_dir = os.environ["SHARED_TOKENIZER_DIR_ENV"]

data = json.loads(config_path.read_text())
changed = 0
for step in data.get("steps", []):
    cfg = step.get("config")
    if not isinstance(cfg, dict):
        continue
    for key in ("tokenizer_name", "paligemma_tokenizer_name"):
        if cfg.get(key) == tokenizer_repo_id:
            cfg[key] = local_tokenizer_dir
            changed += 1

if changed:
    config_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Rewrote {changed} tokenizer reference(s) in {config_path}")
else:
    print(f"No tokenizer references to rewrite in {config_path}")
PY
}

write_ready_marker() {
  mkdir -p "${SHARED_RUNTIME_DIR}"
  cat > "${READY_FILE}" <<EOF
ready=1
created_at=$(date -Iseconds)
project_root=${PROJECT_ROOT}
shared_venv=${SHARED_VENV}
shared_hf_home=${SHARED_HF_HOME}
shared_model_dir=${SHARED_MODEL_DIR}
shared_tokenizer_dir=${SHARED_TOKENIZER_DIR}
model_repo_id=${MODEL_REPO_ID}
tokenizer_repo_id=${TOKENIZER_REPO_ID}
EOF
  log_info "Ready marker written: ${READY_FILE}"
}

ensure_project_venv_link() {
  local project_venv="${PROJECT_ROOT}/.venv"
  local shared_real
  shared_real="$(readlink -f "${SHARED_VENV}")"
  if [[ -L "${project_venv}" ]]; then
    local current_real
    current_real="$(readlink -f "${project_venv}" || true)"
    if [[ "${current_real}" == "${shared_real}" ]]; then
      log_info "Project .venv already linked to shared venv."
      return 0
    fi
  fi

  if [[ -e "${project_venv}" && "${FORCE_LINK}" != "true" ]]; then
    log_err "Project .venv exists and is not the shared symlink: ${project_venv}"
    log_err "Use --force-link to move it aside automatically."
    return 1
  fi

  if [[ -e "${project_venv}" && "${FORCE_LINK}" == "true" ]]; then
    local backup="${PROJECT_ROOT}/.venv.backup.$(date +%s)"
    mv "${project_venv}" "${backup}"
    log_warn "Moved existing .venv to backup: ${backup}"
  fi

  ln -sfn "${SHARED_VENV}" "${project_venv}"
  log_info "Linked ${project_venv} -> ${SHARED_VENV}"
}

run_wrapped_trainpi05() {
  local subcmd="$1"
  shift || true
  local -a cmd
  cmd=(
    bash "${TRAINPI05_SH}" "${subcmd}"
    "--hf-home" "${SHARED_HF_HOME}"
    "--pretrained-path" "${SHARED_MODEL_DIR}"
    "--offline_pretrain_load"
  )
  if [[ "${ENABLE_PROXY}" == "true" ]]; then
    cmd+=(
      "--proxy"
      "--http-proxy" "${HTTP_PROXY_VALUE}"
      "--https-proxy" "${HTTPS_PROXY_VALUE}"
    )
  fi
  cmd+=("$@")
  log_info "Run: ${cmd[*]}"
  "${cmd[@]}"
}

run_wrapped_trainpi05_online_rl() {
  local subcmd="$1"
  shift || true
  local -a cmd
  cmd=(
    bash "${TRAINPI05_ONLINE_RL_SH}" "${subcmd}"
    "--hf-home" "${SHARED_HF_HOME}"
    "--policy-pretrained-path" "${SHARED_MODEL_DIR}"
    "--offline_pretrain_load"
  )
  if [[ "${ENABLE_PROXY}" == "true" ]]; then
    cmd+=(
      "--proxy"
      "--http-proxy" "${HTTP_PROXY_VALUE}"
      "--https-proxy" "${HTTPS_PROXY_VALUE}"
    )
  fi
  cmd+=("$@")
  log_info "Run: ${cmd[*]}"
  "${cmd[@]}"
}

run_init() {
  apply_proxy_if_needed
  apply_shared_hf_env
  acquire_lock

  if [[ -f "${READY_FILE}" && "${REFRESH_VENV}" != "true" && "${REFRESH_MODEL}" != "true" && "${REFRESH_TOKENIZER}" != "true" ]]; then
    log_info "Ready marker already exists, validating shared runtime."
    if validate_shared_runtime; then
      return 0
    fi
    log_warn "Shared runtime validation failed, rebuilding shared assets."
  fi

  rm -f "${READY_FILE}"
  prepare_shared_venv
  maybe_login_hf
  maybe_download_model
  maybe_download_tokenizer
  rewrite_preprocessor_tokenizer_paths
  validate_shared_runtime
  write_ready_marker
  log_info "Shared init completed."
}

run_link() {
  apply_proxy_if_needed
  apply_shared_hf_env
  wait_for_ready
  validate_shared_runtime
  ensure_project_venv_link
}

ensure_runtime_ready_for_training() {
  if [[ "${SKIP_INIT_ENV}" == "true" ]]; then
    log_warn "Skip init env is enabled, run link+validate only."
  else
    run_init
  fi
  run_link
}

run_check() {
  ensure_runtime_ready_for_training
  run_wrapped_trainpi05 check "${EXTRA_ARGS[@]}"
}

run_smoke() {
  ensure_runtime_ready_for_training
  run_wrapped_trainpi05 smoke "${EXTRA_ARGS[@]}"
}

run_train() {
  ensure_runtime_ready_for_training
  run_wrapped_trainpi05 train "${EXTRA_ARGS[@]}"
}

run_train_only() {
  SKIP_INIT_ENV="true"
  run_train
}

run_online_check() {
  ensure_runtime_ready_for_training
  run_wrapped_trainpi05_online_rl check "${EXTRA_ARGS[@]}"
}

run_online_learner() {
  ensure_runtime_ready_for_training
  run_wrapped_trainpi05_online_rl learner "${EXTRA_ARGS[@]}"
}

run_online_actor() {
  ensure_runtime_ready_for_training
  run_wrapped_trainpi05_online_rl actor "${EXTRA_ARGS[@]}"
}

run_bootstrap() {
  run_init
  run_link
  run_wrapped_trainpi05 check "${EXTRA_ARGS[@]}"
}

case "${ACTION}" in
  init)
    run_init
    ;;
  link)
    run_link
    ;;
  check)
    run_check
    ;;
  smoke)
    run_smoke
    ;;
  train)
    run_train
    ;;
  train-only)
    run_train_only
    ;;
  online-check)
    run_online_check
    ;;
  online-learner)
    run_online_learner
    ;;
  online-actor)
    run_online_actor
    ;;
  bootstrap)
    run_bootstrap
    ;;
  *)
    log_err "Unknown command: ${ACTION}"
    usage
    exit 2
    ;;
esac
