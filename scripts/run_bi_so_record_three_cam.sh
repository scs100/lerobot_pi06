#!/usr/bin/env bash
# Backward-compatible entrypoint. Defaults to RL/HIL mode.
# For explicit modes, use:
#   scripts/run_bi_so_record_three_cam_rl.sh
#   scripts/run_bi_so_record_three_cam_ft.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "INFO: run_bi_so_record_three_cam.sh now defaults to RL/HIL mode." >&2
echo "INFO: Use run_bi_so_record_three_cam_ft.sh for clean finetune demos." >&2

exec ./scripts/run_bi_so_record_three_cam_rl.sh "$@"
