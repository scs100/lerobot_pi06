# PI05 RECAP-lite（4090 采集 + A100x8 离线训练）

> 目标：用现有代码跑通一轮  
> `采集 -> rsync上云 -> value训练 -> value推理写回adv/indicator -> ACP训练 -> rsync回传 -> 4090评测`

## 0) 一次性约定（两台机器都先设置）

```bash
export RUN_ID="$(date +%F_%H-%M-%S)"
export TASK_NAME="so101_recap_lite"
export RECAP_REPO_ID="local/${TASK_NAME}_r1_${RUN_ID}"
export EVAL_REPO_ID="local/${TASK_NAME}_eval_${RUN_ID}"

export LOCAL_PROJECT_ROOT="/media/jushen/stone-shi/code/mylong/lerobot_pi06"
export CLOUD_PROJECT_ROOT="/path/to/lerobot_pi06"

export DATASET_ROOT_LOCAL="/media/jushen/stone-shi/lerobot_v30"
export DATASET_ROOT_CLOUD="/path/to/lerobot_v30"

export BASE_POLICY_PATH_LOCAL="/path/to/pi05_ft/checkpoints/005000/pretrained_model"
export BASE_POLICY_PATH_CLOUD="/path/to/pi05_ft/checkpoints/005000/pretrained_model"

export VALUE_OUT_CLOUD_ROOT="/path/to/checkpoints/value"
export ACP_OUT_CLOUD_ROOT="/path/to/checkpoints/acp"
export ACP_OUT_LOCAL_ROOT="/media/jushen/stone-shi/lerobot_pi06/checkpoints/acp"

export CLOUD_SSH="user@a100-host"
```

## 1) 4090：在线采集（含干预 + 成功/失败标注）

```bash
cd "${LOCAL_PROJECT_ROOT}"
bash scripts/training/run_pi05_recap_lite.sh collect \
  --run-id "${RUN_ID}" \
  --task-name "${TASK_NAME}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-local "${DATASET_ROOT_LOCAL}" \
  --base-policy-path-local "${BASE_POLICY_PATH_LOCAL}" \
  --camera-env "scripts/teleop/so101_bi_three_cam.env" \
  --dataset-num-episodes 80
```

## 2) 4090：rsync 采集数据到 A100

```bash
cd "${LOCAL_PROJECT_ROOT}"
bash scripts/training/run_pi05_recap_lite.sh sync-up \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-local "${DATASET_ROOT_LOCAL}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --cloud-ssh "${CLOUD_SSH}"
```

## 3) A100x8：离线 Value + ACP 训练

```bash
cd "${CLOUD_PROJECT_ROOT}"

bash scripts/training/run_pi05_recap_lite.sh value-train \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}" \
  --cloud-num-processes 8 \
  --cloud-cuda-visible-devices 0,1,2,3,4,5,6,7

bash scripts/training/run_pi05_recap_lite.sh value-infer \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}"

bash scripts/training/run_pi05_recap_lite.sh acp-train \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --base-policy-path-cloud "${BASE_POLICY_PATH_CLOUD}" \
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}" \
  --cloud-num-processes 8 \
  --cloud-cuda-visible-devices 0,1,2,3,4,5,6,7
```

## 4) 4090：rsync 拉回 ACP checkpoint

```bash
cd "${LOCAL_PROJECT_ROOT}"
bash scripts/training/run_pi05_recap_lite.sh sync-down \
  --run-id "${RUN_ID}" \
  --cloud-ssh "${CLOUD_SSH}" \
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}" \
  --acp-out-local-root "${ACP_OUT_LOCAL_ROOT}"
```

## 5) 4090：ACP 推理评测 + 报告

```bash
cd "${LOCAL_PROJECT_ROOT}"
bash scripts/training/run_pi05_recap_lite.sh eval \
  --run-id "${RUN_ID}" \
  --task-name "${TASK_NAME}" \
  --eval-repo-id "${EVAL_REPO_ID}" \
  --dataset-root-local "${DATASET_ROOT_LOCAL}" \
  --acp-out-local-root "${ACP_OUT_LOCAL_ROOT}" \
  --camera-env "scripts/teleop/so101_bi_three_cam.env" \
  --dataset-num-episodes-eval 20
```

## 6) 最小检查（每轮都看）

```bash
lerobot-dataset-report --dataset "${RECAP_REPO_ID}" --root "${DATASET_ROOT_LOCAL}"
lerobot-dataset-report --dataset "${EVAL_REPO_ID}" --root "${DATASET_ROOT_LOCAL}"
```

- `success_ratio_labeled_episodes`：是否提升。  
- `indicator_positive_ratio`（`value-infer` 日志）：建议在 `0.2~0.4`。  
- 输出目录均按 `RUN_ID` 新建，默认防覆盖；要复用旧目录需显式加覆盖参数。  

## 7) 先做一次小样本 dry-run（强烈建议）

- 采集：`--dataset-num-episodes 5`  
- Value：`--value-steps 500 --value-batch-size 8`  
- ACP：`--acp-steps 1000 --acp-batch-size 4`  
- 先确认整链路可跑，再开正式轮次。  

## 8) 用 `run_345_once.sh` 一键串行跑 3/4/5（推荐）

脚本位置：`scripts/training/run_345_once.sh`  
执行顺序固定：`value-train -> value-infer -> acp-train`。  
默认预设：`single_4090_nearprod`（单卡 4090，按 8 卡参考有效 batch 自动缩放步数）。

### 8.1 先检查命令拼接（不执行）

```bash
cd "${CLOUD_PROJECT_ROOT}"
bash scripts/training/run_345_once.sh \
  --preset single_a100_smoke \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --base-policy-path-cloud "${BASE_POLICY_PATH_CLOUD}" \
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}" \
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}" \
  --dry-run
```

### 8.2 单卡 smoke（最小闭环）

```bash
cd "${CLOUD_PROJECT_ROOT}"
bash scripts/training/run_345_once.sh \
  --preset single_a100_smoke \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --base-policy-path-cloud "${BASE_POLICY_PATH_CLOUD}" \
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}" \
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}"
```

### 8.3 单卡 near-prod（默认 4090）

```bash
cd "${CLOUD_PROJECT_ROOT}"
bash scripts/training/run_345_once.sh \
  --preset single_4090_nearprod \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --base-policy-path-cloud "${BASE_POLICY_PATH_CLOUD}" \
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}" \
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}"
```

如在单卡 A100 上运行，可显式指定：`--preset single_a100_nearprod`。

### 8.4 4 卡 / 8 卡预设

```bash
# 4 卡
bash scripts/training/run_345_once.sh \
  --preset four_gpu_prod \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --base-policy-path-cloud "${BASE_POLICY_PATH_CLOUD}" \
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}" \
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}"

# 8 卡
bash scripts/training/run_345_once.sh \
  --preset eight_gpu_prod \
  --run-id "${RUN_ID}" \
  --recap-repo-id "${RECAP_REPO_ID}" \
  --dataset-root-cloud "${DATASET_ROOT_CLOUD}" \
  --base-policy-path-cloud "${BASE_POLICY_PATH_CLOUD}" \
  --value-out-cloud-root "${VALUE_OUT_CLOUD_ROOT}" \
  --acp-out-cloud-root "${ACP_OUT_CLOUD_ROOT}"
```

### 8.5 参数说明（最常改）

- `value/acp` 的训练强度主要由 `batch_size * num_processes * steps` 决定。  
- `--auto-scale-steps true` 时（默认随预设开启），会按 8 卡参考有效 batch 自动给出等效步数。  
- `value-infer` 不使用 `steps`，主要关注日志中的 `indicator_positive_ratio`。  
- `--allow-existing-dst true` 可复用已存在输出目录（默认 false，防覆盖）。  

