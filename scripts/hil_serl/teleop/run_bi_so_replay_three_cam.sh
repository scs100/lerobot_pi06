#!/usr/bin/env bash
# Dual-arm SO101 replay from a recorded LeRobot dataset episode.
#
# Usage:
# conda activate lerobot-pi06

#   set -a && source scripts/hil_serl/teleop/so101_bi_three_cam.env && set +a
#   export DATASET_REPO_ID=<HF_USERNAME_OR_ORG>/<DATASET_NAME>
#   export DATASET_EPISODE=0
#   ./scripts/hil_serl/teleop/run_bi_so_replay_three_cam.sh
#
# Notes:
# - Replay uses robot joints only, cameras are not required in replay command.
# - Make sure the robot workspace is clear before replaying.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

LERO_CMD="$(command -v lerobot-replay 2>/dev/null || true)"
if [[ -z "$LERO_CMD" ]]; then
  for d in "$HOME/miniconda3/envs"/*/bin "$HOME/anaconda3/envs"/*/bin "$HOME/mambaforge/envs"/*/bin; do
    if [[ -x "${d}/lerobot-replay" ]]; then
      LERO_CMD="${d}/lerobot-replay"
      break
    fi
  done
fi
if [[ -z "$LERO_CMD" ]]; then
  echo "ERROR: lerobot-replay not in PATH. Activate your conda env (e.g. conda activate lerobot-pi06)." >&2
  exit 127
fi

LEFT_FOLLOWER_PORT="${LEFT_FOLLOWER_PORT:-/dev/ttyACM3}"
RIGHT_FOLLOWER_PORT="${RIGHT_FOLLOWER_PORT:-/dev/ttyACM2}"
ROBOT_ID="${ROBOT_ID:-my_so101_follower}"

DATASET_REPO_ID="${DATASET_REPO_ID:-}"
DATASET_EPISODE="${DATASET_EPISODE:-0}"
DATASET_ROOT="${DATASET_ROOT:-}"
PLAY_SOUNDS="${PLAY_SOUNDS:-false}"

if [[ -z "$DATASET_REPO_ID" ]]; then
  echo "ERROR: DATASET_REPO_ID is required. Example: export DATASET_REPO_ID=my-hf-user/so101_three_cam_round1" >&2
  exit 1
fi

ARGS=(
  "$LERO_CMD"
  --robot.type=bi_so_follower
  --robot.left_arm_config.port="${LEFT_FOLLOWER_PORT}"
  --robot.right_arm_config.port="${RIGHT_FOLLOWER_PORT}"
  --robot.left_arm_config.disable_torque_on_disconnect=false
  --robot.right_arm_config.disable_torque_on_disconnect=false
  --robot.id="${ROBOT_ID}"
  --dataset.repo_id="${DATASET_REPO_ID}"
  --dataset.episode="${DATASET_EPISODE}"
  --play_sounds="${PLAY_SOUNDS}"
)

if [[ -n "${DATASET_ROOT}" ]]; then
  ARGS+=(--dataset.root="${DATASET_ROOT}")
fi

echo "Mode: Replay episode from dataset." >&2
echo "Replay: repo_id=${DATASET_REPO_ID}, episode=${DATASET_EPISODE}" >&2

exec "${ARGS[@]}"
