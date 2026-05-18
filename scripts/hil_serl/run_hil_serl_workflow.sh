#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/hil_serl/run_hil_serl_workflow.sh <command> [options] [-- extra_overrides]

Commands:
  check            检查 HIL-SERL 运行依赖与脚本路径。
  step1            执行 step1 全流程：采集分类器数据(默认10条) + 训练分类器。
  step1_collect    仅执行 step1 的采集分类器数据。
  step1_train      仅执行 step1 的训练分类器。
  step2            执行 step2：采集 demo 数据(默认25条)。
  step3_learner    执行 step3：启动 learner（先启动）。
  step3_actor      执行 step3：启动 actor（另一个终端）。
  step4_deploy     执行 step4：纯策略部署推理（无接管、无数据写入）。

Core options:
  --env-config PATH               gym_manipulator 配置（step1/step2 必填）
  --reward-train-config PATH      reward classifier 训练配置（step1_train/step1 必填）
  --train-config PATH             actor/learner 训练配置（step3 必填）
  --dataset-repo-id ID            覆盖 dataset.repo_id（step1/2/3）
  --dataset-root PATH             覆盖 dataset.root（step1/2/3）
  --dataset-task TEXT             覆盖 dataset.task（step1/2），或 env.task（step3）
  --episodes N                    step1 默认 10；step2 默认 25
  --output-dir PATH               覆盖 output_dir（step1_train/step3/step4自动找模型）
  --resume true|false             覆盖 resume（step3_actor 默认自动 true）
  --policy-path PATH              可选，覆盖 policy.path（step3，仅需预训练策略时）或部署模型目录（step4）
  --env-file PATH                 部署 env 文件，默认 scripts/hil_serl/teleop/so101_bi_three_cam.env
  --push-to-hub true|false        step1/2 数据采集是否上传，默认 false
  --display-data true|false       step4 是否显示可视化，默认 false
  --deploy-duration-s N           step4 纯推理时长秒数，默认 86400
  --python PATH                   指定 python，可覆盖自动探测
  --dry-run                       仅打印命令，不执行

Pass-through:
  在参数最后加 `--`，后面的参数会原样透传到底层 python 命令。
  例如: -- --batch_size=16 --policy.online_steps=800

Examples:
  # 推荐配置目录：
  #   scripts/hil_serl/configs/
  #
  # Step1: 采集 10 条用于分类器 + 训练分类器
  bash scripts/hil_serl/run_hil_serl_workflow.sh step1 \
    --env-config scripts/hil_serl/configs/so101_hil_serl_env_step1_classifier_collect.neo.json \
    --reward-train-config scripts/hil_serl/configs/so101_hil_serl_reward_classifier_train.neo.json \
    --dataset-root /data/hil_serl/classifier_round1 \
    --dataset-repo-id local/hilserl_classifier_round1

  # Step2: 采集 25 条 demo
  bash scripts/hil_serl/run_hil_serl_workflow.sh step2 \
    --env-config scripts/hil_serl/configs/so101_hil_serl_env_step2_demo_collect.neo.json \
    --episodes 25 \
    --dataset-root /data/hil_serl/demo_round1 \
    --dataset-repo-id local/hilserl_demo_round1

  # Step3: 两个终端分别执行 learner / actor
  bash scripts/hil_serl/run_hil_serl_workflow.sh step3_learner \
    --train-config scripts/hil_serl/configs/so101_hil_serl_train_sac.neo.json \
    --output-dir outputs/hil_serl/run_001

  bash scripts/hil_serl/run_hil_serl_workflow.sh step3_actor \
    --train-config scripts/hil_serl/configs/so101_hil_serl_train_sac.neo.json \
    --output-dir outputs/hil_serl/run_001

  # Step4: 纯部署（默认从 output-dir 下自动选最新 checkpoint/pretrained_model）
  bash scripts/hil_serl/run_hil_serl_workflow.sh step4_deploy \
    --output-dir outputs/hil_serl/run_001 \
    --env-file scripts/hil_serl/teleop/so101_bi_three_cam.env \
    --deploy-duration-s 3600
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
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"

COMMAND="${1:-}"
if [[ -z "${COMMAND}" || "${COMMAND}" == "-h" || "${COMMAND}" == "--help" || "${COMMAND}" == "help" ]]; then
  usage
  exit 0
fi
shift || true

DEFAULT_PYTHON="${ROOT_DIR}/.venv/bin/python"
if [[ -x "${DEFAULT_PYTHON}" ]]; then
  PYTHON_BIN="${DEFAULT_PYTHON}"
else
  PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
fi

ENV_CONFIG=""
REWARD_TRAIN_CONFIG=""
TRAIN_CONFIG=""
DATASET_REPO_ID=""
DATASET_ROOT=""
DATASET_TASK=""
EPISODES=""
OUTPUT_DIR=""
RESUME=""
RESUME_SET="false"
POLICY_PATH=""
ENV_FILE="${ROOT_DIR}/scripts/hil_serl/teleop/so101_bi_three_cam.env"
PUSH_TO_HUB="false"
DISPLAY_DATA="false"
DEPLOY_DURATION_S="86400"
DRY_RUN="false"

EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-config) ENV_CONFIG="$2"; shift 2 ;;
    --reward-train-config) REWARD_TRAIN_CONFIG="$2"; shift 2 ;;
    --train-config) TRAIN_CONFIG="$2"; shift 2 ;;
    --dataset-repo-id) DATASET_REPO_ID="$2"; shift 2 ;;
    --dataset-root) DATASET_ROOT="$2"; shift 2 ;;
    --dataset-task) DATASET_TASK="$2"; shift 2 ;;
    --episodes) EPISODES="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --resume) RESUME="$2"; RESUME_SET="true"; shift 2 ;;
    --policy-path) POLICY_PATH="$2"; shift 2 ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --push-to-hub) PUSH_TO_HUB="$2"; shift 2 ;;
    --display-data) DISPLAY_DATA="$2"; shift 2 ;;
    --deploy-duration-s) DEPLOY_DURATION_S="$2"; shift 2 ;;
    --python) PYTHON_BIN="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *)
      log_err "未知参数: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${PYTHON_BIN}" ]]; then
  log_err "未找到 python，请先激活环境（例如 conda activate lerobot-pi06）"
  exit 127
fi

require_file() {
  local path="$1"
  local label="$2"
  if [[ -z "${path}" ]]; then
    log_err "${label} 不能为空"
    exit 2
  fi
  if [[ ! -f "${path}" ]]; then
    log_err "${label} 文件不存在: ${path}"
    exit 1
  fi
}

run_cmd() {
  local -a cmd=("$@")
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[DRY-RUN] '
    printf '%q ' "${cmd[@]}"
    printf '\n'
    return 0
  fi
  "${cmd[@]}"
}

assert_dataset_root_not_exists() {
  if [[ -n "${DATASET_ROOT}" && -e "${DATASET_ROOT}" ]]; then
    log_err "dataset.root 已存在，LeRobotDataset.create 会因 exist_ok=false 失败: ${DATASET_ROOT}"
    log_err "请改成一个全新目录，避免覆盖历史数据。"
    exit 1
  fi
}

run_record_mode() {
  local config_path="$1"
  local episodes="$2"
  local terminate_on_success="$3"

  require_file "${config_path}" "--env-config"
  assert_dataset_root_not_exists

  log_warn "真机执行前请确认：急停可用、工作空间清空、相机/串口映射正确。"
  log_info "record: episodes=${episodes}, terminate_on_success=${terminate_on_success}, push_to_hub=${PUSH_TO_HUB}"

  local -a cmd=(
    env "PYTHONPATH=${ROOT_DIR}/src:${PYTHONPATH:-}"
    "${PYTHON_BIN}" -m lerobot.rl.gym_manipulator
    "--config_path=${config_path}"
    "--mode=record"
    "--dataset.num_episodes_to_record=${episodes}"
    "--env.processor.reset.terminate_on_success=${terminate_on_success}"
    "--dataset.push_to_hub=${PUSH_TO_HUB}"
  )

  if [[ -n "${DATASET_REPO_ID}" ]]; then
    cmd+=("--dataset.repo_id=${DATASET_REPO_ID}")
  fi
  if [[ -n "${DATASET_ROOT}" ]]; then
    cmd+=("--dataset.root=${DATASET_ROOT}")
  fi
  if [[ -n "${DATASET_TASK}" ]]; then
    cmd+=("--dataset.task=${DATASET_TASK}")
  fi
  if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  run_cmd "${cmd[@]}"
}

run_step1_collect() {
  local episodes="${EPISODES:-10}"
  local terminate_on_success="false"
  run_record_mode "${ENV_CONFIG}" "${episodes}" "${terminate_on_success}"
}

run_step1_train() {
  require_file "${REWARD_TRAIN_CONFIG}" "--reward-train-config"
  if [[ -n "${OUTPUT_DIR}" && -d "${OUTPUT_DIR}" && "${RESUME}" != "true" ]]; then
    log_err "step1_train 输出目录已存在且 --resume 不是 true: ${OUTPUT_DIR}"
    exit 1
  fi

  local -a cmd=(
    env "PYTHONPATH=${ROOT_DIR}/src:${PYTHONPATH:-}"
    "${PYTHON_BIN}" -m lerobot.scripts.lerobot_train
    "--config_path=${REWARD_TRAIN_CONFIG}"
  )
  if [[ -n "${OUTPUT_DIR}" ]]; then
    cmd+=("--output_dir=${OUTPUT_DIR}")
  fi
  if [[ "${RESUME_SET}" == "true" ]]; then
    cmd+=("--resume=${RESUME}")
  fi
  if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  run_cmd "${cmd[@]}"
}

run_step2() {
  local episodes="${EPISODES:-25}"
  local terminate_on_success="true"
  run_record_mode "${ENV_CONFIG}" "${episodes}" "${terminate_on_success}"
}

run_step3_learner() {
  require_file "${TRAIN_CONFIG}" "--train-config"
  if [[ -n "${OUTPUT_DIR}" && -d "${OUTPUT_DIR}" && "${RESUME}" != "true" ]]; then
    log_err "learner 输出目录已存在且 --resume 不是 true: ${OUTPUT_DIR}"
    log_err "为避免覆盖历史 checkpoint，请更换输出目录或显式设置 --resume true。"
    exit 1
  fi

  log_warn "请先启动 learner，再在另一个终端启动 actor。"
  local -a cmd=(
    env "PYTHONPATH=${ROOT_DIR}/src:${PYTHONPATH:-}"
    "${PYTHON_BIN}" -m lerobot.rl.learner
    "--config_path=${TRAIN_CONFIG}"
  )

  if [[ -n "${OUTPUT_DIR}" ]]; then
    cmd+=("--output_dir=${OUTPUT_DIR}")
  fi
  if [[ "${RESUME_SET}" == "true" ]]; then
    cmd+=("--resume=${RESUME}")
  fi
  if [[ -n "${POLICY_PATH}" ]]; then
    cmd+=("--policy.path=${POLICY_PATH}")
  fi
  if [[ -n "${DATASET_REPO_ID}" ]]; then
    cmd+=("--dataset.repo_id=${DATASET_REPO_ID}")
  fi
  if [[ -n "${DATASET_ROOT}" ]]; then
    cmd+=("--dataset.root=${DATASET_ROOT}")
  fi
  if [[ -n "${DATASET_TASK}" ]]; then
    cmd+=("--env.task=${DATASET_TASK}")
  fi
  if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  run_cmd "${cmd[@]}"
}

run_step3_actor() {
  require_file "${TRAIN_CONFIG}" "--train-config"

  local actor_resume="${RESUME}"
  if [[ "${RESUME_SET}" != "true" ]]; then
    actor_resume="true"
    log_info "step3_actor 默认设置 --resume=true（与 learner 共用 output_dir）。"
  fi

  local -a cmd=(
    env "PYTHONPATH=${ROOT_DIR}/src:${PYTHONPATH:-}"
    "${PYTHON_BIN}" -m lerobot.rl.actor
    "--config_path=${TRAIN_CONFIG}"
    "--resume=${actor_resume}"
  )

  if [[ -n "${OUTPUT_DIR}" ]]; then
    cmd+=("--output_dir=${OUTPUT_DIR}")
  fi
  if [[ -n "${POLICY_PATH}" ]]; then
    cmd+=("--policy.path=${POLICY_PATH}")
  fi
  if [[ -n "${DATASET_REPO_ID}" ]]; then
    cmd+=("--dataset.repo_id=${DATASET_REPO_ID}")
  fi
  if [[ -n "${DATASET_ROOT}" ]]; then
    cmd+=("--dataset.root=${DATASET_ROOT}")
  fi
  if [[ -n "${DATASET_TASK}" ]]; then
    cmd+=("--env.task=${DATASET_TASK}")
  fi
  if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  run_cmd "${cmd[@]}"
}

resolve_policy_path_for_deploy() {
  if [[ -n "${POLICY_PATH}" ]]; then
    return 0
  fi
  if [[ -z "${OUTPUT_DIR}" ]]; then
    log_err "step4_deploy 需要 --policy-path 或 --output-dir。"
    exit 2
  fi

  local -a candidates=()
  shopt -s nullglob
  candidates=("${OUTPUT_DIR}"/checkpoints/*/pretrained_model)
  shopt -u nullglob

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    log_err "在 ${OUTPUT_DIR}/checkpoints 下未找到 pretrained_model。"
    exit 1
  fi

  local latest=""
  local item
  for item in "${candidates[@]}"; do
    latest="${item}"
  done
  POLICY_PATH="${latest}"
  log_info "step4_deploy 自动使用最新策略: ${POLICY_PATH}"
}

run_step4_deploy() {
  resolve_policy_path_for_deploy
  require_file "${ENV_FILE}" "--env-file"

  if [[ ! -f "${POLICY_PATH}/model.safetensors" ]]; then
    log_err "policy-path 缺少 model.safetensors: ${POLICY_PATH}"
    exit 1
  fi

  log_warn "部署前请确认：周围无人员障碍物、急停可达、机械臂工作空间已清空。"

  local -a cmd=(
    bash "${ROOT_DIR}/scripts/training/run_ft_pi05_single_episode_infer.sh"
    --env-file "${ENV_FILE}"
    --policy-path "${POLICY_PATH}"
    --episode-time-s "${DEPLOY_DURATION_S}"
    --display-data "${DISPLAY_DATA}"
    --pure-infer true
  )
  if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  run_cmd "${cmd[@]}"
}

run_check() {
  log_info "python=${PYTHON_BIN}"
  run_cmd "${PYTHON_BIN}" -V

  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[DRY-RUN] env PYTHONPATH=%q %q - <<'"'"'PY'"'"' ... PY\n' "${ROOT_DIR}/src:${PYTHONPATH:-}" "${PYTHON_BIN}"
  else
    env "PYTHONPATH=${ROOT_DIR}/src:${PYTHONPATH:-}" "${PYTHON_BIN}" - <<'PY'
import importlib
import sys

mods = [
    "lerobot.rl.gym_manipulator",
    "lerobot.rl.learner",
    "lerobot.rl.actor",
    "lerobot.scripts.lerobot_train",
]
missing = []
for name in mods:
    try:
        importlib.import_module(name)
    except Exception as exc:  # pragma: no cover
        missing.append((name, repr(exc)))

if missing:
    print("[ERR] HIL-SERL 依赖检查失败：")
    for name, err in missing:
        print(f"  - {name}: {err}")
    sys.exit(1)

print("[INFO] HIL-SERL 关键依赖检查通过。")
PY
  fi

  if [[ -f "${ROOT_DIR}/scripts/training/run_ft_pi05_single_episode_infer.sh" ]]; then
    log_info "deploy 脚本存在: scripts/training/run_ft_pi05_single_episode_infer.sh"
  else
    log_warn "deploy 脚本缺失: scripts/training/run_ft_pi05_single_episode_infer.sh"
  fi
}

case "${COMMAND}" in
  check)
    run_check
    ;;
  step1_collect)
    run_step1_collect
    ;;
  step1_train)
    run_step1_train
    ;;
  step1)
    run_step1_collect
    run_step1_train
    ;;
  step2)
    run_step2
    ;;
  step3_learner)
    run_step3_learner
    ;;
  step3_actor)
    run_step3_actor
    ;;
  step4_deploy)
    run_step4_deploy
    ;;
  *)
    log_err "未知命令: ${COMMAND}"
    usage
    exit 2
    ;;
esac
