# HIL-SERL 分步启动脚本

本目录把论文里的核心流程拆成可执行入口（step1 ~ step4）：

1. **Step1**：采集约 10 条分类器数据 + 训练成功分类器  
2. **Step2**：采集 20~30 条示范，用于初始化 Demo Buffer  
3. **Step3**：启动 actor / learner 异步训练，人工可随时接管矫正  
4. **Step4**：部署策略做纯推理（无人工接管、无数据写入）

---

## 主入口

```bash
bash scripts/hil_serl/run_hil_serl_workflow.sh --help
```

---

## 快捷入口

```bash
# 依赖检查
bash scripts/hil_serl/run_hil_serl_check.sh

# Step1: 采集分类器数据 + 训练分类器
bash scripts/hil_serl/run_hil_serl_step1_classifier.sh ...

# Step2: 采集 demos
bash scripts/hil_serl/run_hil_serl_step2_collect_demos.sh ...

# Step3: 两个终端分别启动 learner / actor
bash scripts/hil_serl/run_hil_serl_step3_learner.sh ...
bash scripts/hil_serl/run_hil_serl_step3_actor.sh ...

# Step4: 纯部署推理
bash scripts/hil_serl/run_hil_serl_step4_deploy.sh ...
```

---

## 可直接复制执行（当前仓库）

下面这组命令基于仓库现有配置：

- `scripts/hil_serl/configs/so101_hil_serl_env_step1_classifier_collect.neo.json`
- `scripts/hil_serl/configs/so101_hil_serl_env_step2_demo_collect.neo.json`
- `scripts/hil_serl/configs/so101_hil_serl_reward_classifier_train.neo.json`
- `scripts/hil_serl/configs/so101_hil_serl_train_sac.neo.json`
- 相机/串口环境：`scripts/teleop/so101_bi_three_cam.env`

### 0) 初始化变量

```bash
cd /home/neo/code/opensource/so101/lerobot_pi06

export HIL_RUN_ID="$(date +%F_%H-%M-%S)"
export HIL_ENV_CFG_STEP1="scripts/hil_serl/configs/so101_hil_serl_env_step1_classifier_collect.neo.json"
export HIL_ENV_CFG_STEP2="scripts/hil_serl/configs/so101_hil_serl_env_step2_demo_collect.neo.json"
export HIL_REWARD_CFG="scripts/hil_serl/configs/so101_hil_serl_reward_classifier_train.neo.json"
export HIL_TRAIN_CFG="scripts/hil_serl/configs/so101_hil_serl_train_sac.neo.json"

export HIL_TASK="put the phone stand into the shipping box"
export HIL_ROOT="$PWD/outputs/hil_serl/${HIL_RUN_ID}"

export HIL_CLASSIFIER_DATA_ROOT="$HIL_ROOT/datasets/classifier"
export HIL_CLASSIFIER_DATA_REPO="local/hil_serl_classifier_${HIL_RUN_ID}"

export HIL_DEMO_DATA_ROOT="$HIL_ROOT/datasets/demos"
export HIL_DEMO_DATA_REPO="local/hil_serl_demos_${HIL_RUN_ID}"

export HIL_TRAIN_OUT="$HIL_ROOT/train_run"
```

### 1) 环境检查 + 同步三相机参数到训练配置

```bash
bash scripts/hil_serl/run_hil_serl_check.sh

cp "$HIL_ENV_CFG_STEP1" "${HIL_ENV_CFG_STEP1%.json}.bak.${HIL_RUN_ID}.json"
cp "$HIL_ENV_CFG_STEP2" "${HIL_ENV_CFG_STEP2%.json}.bak.${HIL_RUN_ID}.json"
cp "$HIL_TRAIN_CFG" "${HIL_TRAIN_CFG%.json}.bak.${HIL_RUN_ID}.json"

bash scripts/hil_serl/sync_three_cam_env_to_hil_serl_json.sh \
  --env-file scripts/teleop/so101_bi_three_cam.env \
  --config-path "$HIL_ENV_CFG_STEP1"

bash scripts/hil_serl/sync_three_cam_env_to_hil_serl_json.sh \
  --env-file scripts/teleop/so101_bi_three_cam.env \
  --config-path "$HIL_ENV_CFG_STEP2"

bash scripts/hil_serl/sync_three_cam_env_to_hil_serl_json.sh \
  --env-file scripts/teleop/so101_bi_three_cam.env \
  --config-path "$HIL_TRAIN_CFG"
```

### 2) Step1：采集 10 条分类器数据

```bash
bash scripts/hil_serl/run_hil_serl_workflow.sh step1_collect \
  --env-config "$HIL_ENV_CFG_STEP1" \
  --dataset-root "$HIL_CLASSIFIER_DATA_ROOT" \
  --dataset-repo-id "$HIL_CLASSIFIER_DATA_REPO" \
  --dataset-task "$HIL_TASK" \
  --episodes 10
```

### 3) Step1：训练 reward classifier

```bash
bash scripts/hil_serl/run_hil_serl_workflow.sh step1_train \
  --reward-train-config "$HIL_REWARD_CFG" \
  --output-dir "$HIL_ROOT/reward_classifier_train" \
  -- \
  --dataset.repo_id="$HIL_CLASSIFIER_DATA_REPO" \
  --dataset.root="$HIL_CLASSIFIER_DATA_ROOT" \
  --policy.num_cameras=3
```

### 4) 获取 reward classifier 模型目录（给 step2/step3 用）

```bash
export HIL_REWARD_MODEL_DIR="$(ls -d "$HIL_ROOT/reward_classifier_train"/checkpoints/*/pretrained_model | sort | tail -n1)"
test -f "$HIL_REWARD_MODEL_DIR/model.safetensors"
```

### 5) Step2：采集 25 条 demos（20~30 都可以）

```bash
bash scripts/hil_serl/run_hil_serl_workflow.sh step2 \
  --env-config "$HIL_ENV_CFG_STEP2" \
  --dataset-root "$HIL_DEMO_DATA_ROOT" \
  --dataset-repo-id "$HIL_DEMO_DATA_REPO" \
  --dataset-task "$HIL_TASK" \
  --episodes 25 \
  -- \
  --env.processor.reward_classifier.pretrained_path="$HIL_REWARD_MODEL_DIR"
```

### 6) Step3：先 learner（终端 A），再 actor（终端 B）

```bash
# terminal A
bash scripts/hil_serl/run_hil_serl_workflow.sh step3_learner \
  --train-config "$HIL_TRAIN_CFG" \
  --output-dir "$HIL_TRAIN_OUT" \
  --dataset-root "$HIL_DEMO_DATA_ROOT" \
  --dataset-repo-id "$HIL_DEMO_DATA_REPO" \
  --dataset-task "$HIL_TASK" \
  -- \
  --env.processor.reward_classifier.pretrained_path="$HIL_REWARD_MODEL_DIR" \
  --policy.online_steps=20000 \
  --policy.online_step_before_learning=64 \
  --wandb.enable=false

# terminal B
bash scripts/hil_serl/run_hil_serl_workflow.sh step3_actor \
  --train-config "$HIL_TRAIN_CFG" \
  --output-dir "$HIL_TRAIN_OUT" \
  --dataset-root "$HIL_DEMO_DATA_ROOT" \
  --dataset-repo-id "$HIL_DEMO_DATA_REPO" \
  --dataset-task "$HIL_TASK" \
  -- \
  --env.processor.reward_classifier.pretrained_path="$HIL_REWARD_MODEL_DIR" \
  --policy.online_steps=20000 \
  --policy.online_step_before_learning=64 \
  --wandb.enable=false
```

### 7) Step4：部署纯推理

```bash
bash scripts/hil_serl/run_hil_serl_workflow.sh step4_deploy \
  --output-dir "$HIL_TRAIN_OUT" \
  --env-file scripts/teleop/so101_bi_three_cam.env \
  --deploy-duration-s 5400 \
  --display-data false
```

---

## 典型执行示例

### Step1

```bash
bash scripts/hil_serl/run_hil_serl_step1_classifier.sh \
  --env-config scripts/hil_serl/configs/so101_hil_serl_env_step1_classifier_collect.neo.json \
  --reward-train-config scripts/hil_serl/configs/so101_hil_serl_reward_classifier_train.neo.json \
  --dataset-root /data/hil_serl/classifier_round1 \
  --dataset-repo-id local/hilserl_classifier_round1
```

### Step2

```bash
bash scripts/hil_serl/run_hil_serl_step2_collect_demos.sh \
  --env-config scripts/hil_serl/configs/so101_hil_serl_env_step2_demo_collect.neo.json \
  --episodes 25 \
  --dataset-root /data/hil_serl/demo_round1 \
  --dataset-repo-id local/hilserl_demo_round1
```

### Step3（两个终端）

```bash
# terminal A
bash scripts/hil_serl/run_hil_serl_step3_learner.sh \
  --train-config scripts/hil_serl/configs/so101_hil_serl_train_sac.neo.json \
  --output-dir outputs/hil_serl/run_001

# terminal B
bash scripts/hil_serl/run_hil_serl_step3_actor.sh \
  --train-config scripts/hil_serl/configs/so101_hil_serl_train_sac.neo.json \
  --output-dir outputs/hil_serl/run_001
```

### Step4

```bash
bash scripts/hil_serl/run_hil_serl_step4_deploy.sh \
  --output-dir outputs/hil_serl/run_001 \
  --env-file scripts/teleop/so101_bi_three_cam.env \
  --deploy-duration-s 3600
```

---

## 安全与目录约束

- 真机运行前先确认：急停、清空工作空间、串口和相机映射正确。
- `scripts/hil_serl/configs/so101_hil_serl_train_sac.neo.json` 使用 `policy.type=sac`，默认不依赖预训练模型。
- `step1/step2` 的 `--dataset-root` 必须是**不存在的新目录**；脚本会拒绝已有目录（LeRobot create 使用 `exist_ok=false`）。
- `step3_learner` 默认不允许覆盖已有 `output_dir`，除非显式 `--resume true`。
- `step3_actor` 默认自动使用 `--resume true`，便于与 learner 共享同一 `output_dir`。
