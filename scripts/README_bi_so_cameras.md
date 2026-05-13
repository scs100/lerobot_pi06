# Bi SO101：相机检测与双臂三相机启动

## 1. 安装 `v4l-utils`（本机执行）

```bash
sudo apt-get update && sudo apt-get install -y v4l-utils
v4l2-ctl --version
```

无 sudo 的环境可用仓库内 OpenCV 探针代替一步骤：`scripts/softenv/probe_v4l_opencv.py`。

## 2. 枚举稳定路径

```bash
ls -l /dev/v4l/by-path/
```

双臂示例通常使用每个物理相机的 `*-video-index0`（`index1` 常为 metadata，勿用作 RGB）。

### 2.1 找第三路：插拔前后对比

```bash
chmod +x scripts/softenv/v4l_snapshot.sh
./scripts/softenv/v4l_snapshot.sh /tmp/v4l-before.txt
# 插上第三路 USB 相机
./scripts/softenv/v4l_snapshot.sh /tmp/v4l-after.txt
diff -u /tmp/v4l-before.txt /tmp/v4l-after.txt
```

新增的 `...-video-index0` 即第三路候选。

### 2.2 自动打印三路 `export`（需已识别到 3 个 index0）

```bash
chmod +x scripts/teleop/auto_export_three_cams.sh
./scripts/teleop/auto_export_three_cams.sh   # 成功时再执行其输出的三行 export
```

若少于 3 路会退出码 1 并列出当前设备；映射顺序不对时可手动改 `CAM_LEFT`/`CAM_RIGHT`/`CAM_FRONT`。

## 3. 检测格式 / 快速抓帧

```bash
chmod +x scripts/teleop/check_bi_so_cameras.sh
./scripts/teleop/check_bi_so_cameras.sh
```

设置第三路相机后：

```bash
export CAM_FRONT=/dev/v4l/by-path/<third-camera>-video-index0
./scripts/teleop/check_bi_so_cameras.sh
```

## 4. 冒烟：双臂 + 仅一路 front（显示）

```bash
chmod +x scripts/teleop/run_bi_so_teleop_three_cam.sh
FRONT_ONLY=1 ./scripts/teleop/run_bi_so_teleop_three_cam.sh
```

（使用右臂配置挂一路 `front`；左臂不传 `cameras` 字段，避免空 JSON。）

可选指定用于冒烟的设备：`CAM_SMOKE=/dev/v4l/by-path/... FRONT_ONLY=1 ./scripts/teleop/run_bi_so_teleop_three_cam.sh`

若报错 `Failed to find Rerun Viewer executable in PATH`，要么[安装 Rerun Viewer](https://rerun.io/docs/getting-started/installing-viewer)，要么先不开可视化：

```bash
DISPLAY_DATA=false FRONT_ONLY=1 ./scripts/teleop/run_bi_so_teleop_three_cam.sh
```

## 5. 正式：双臂 + 三路相机

左右腕画面对调：交换 `CAM_LEFT` / `CAM_RIGHT` 的路径即可。

画面倒置：`export CAM_ROTATION=180`（再运行启动脚本；对应 OpenCV `Cv2Rotation`，可选 `90` / `270`）。

```bash
cp scripts/teleop/so101_bi_three_cam.env.example scripts/teleop/so101_bi_three_cam.env
# 编辑 CAM_FRONT 与各 ttyACM / PCI 路径
set -a && source scripts/teleop/so101_bi_three_cam.env && set +a
./scripts/teleop/run_bi_so_teleop_three_cam.sh
```

标定与电机不一致时，首次连接按 **Enter** 将标定写入舵机。
若不希望每次启动手动按 Enter，可在环境中设置：`export LEROBOT_AUTO_USE_CALIBRATION=true`（检测到本地标定文件时自动写回）。

## 6. 录制为 LeRobot 数据集（分 RL/HIL 与 Finetune 两套）

复用同一份环境变量（串口 + 三路相机）：

```bash
set -a && source scripts/teleop/so101_bi_three_cam.env && set +a
```

### 6.1 RL/HIL 录制（含人工介入 + 成功/失败标注）

```bash
chmod +x scripts/teleop/run_bi_so_record_three_cam_rl.sh
export DATASET_REPO_ID=<HF_USERNAME_OR_ORG>/<DATASET_NAME>
export DATASET_SINGLE_TASK="bimanual pick and place"
export DATASET_NUM_EPISODES=50
export DATASET_EPISODE_TIME_S=35
export DATASET_RESET_TIME_S=20
export DATASET_PUSH_TO_HUB=false
export WAIT_FOR_EPISODE_START=true
export EPISODE_START_KEY=0
export EPISODE_END_KEY=1
export EPISODE_DISCARD_KEY=7
# 可选：改成不常用按键，减少误触
export INTERVENTION_TOGGLE_KEY=9
export EPISODE_SUCCESS_KEY='['
export EPISODE_FAILURE_KEY=']'
./scripts/teleop/run_bi_so_record_three_cam_rl.sh
```

说明：

- RL/HIL 脚本内部调用 `lerobot-human-inloop-record`，适合收集 intervention、失败片段与成功片段，用于后续 value/advantage/ACP 流程。
- `WAIT_FOR_EPISODE_START=true` 时，每个 episode 会等待 `EPISODE_START_KEY`（默认 `0`）后再开始录制。
- 可设置 `EPISODE_END_KEY=1` 结束并保存当前 episode，`EPISODE_DISCARD_KEY=7` 丢弃并重录当前 episode。
- 三路相机默认都按 OpenCV 方式采集；可按设备能力选择 `YUYV` 或 `MJPG`。
- 若三路相机可用帧率不一致（例如 wrist=60、front=30），可分别设置：
`CAM_LEFT_FPS` / `CAM_RIGHT_FPS` / `CAM_FRONT_FPS`（会覆盖 `CAM_FPS`）。
- 若需要更换视频格式（例如把 `MJPG` 改成 `YUYV` 以尝试 30fps），可设置：
`CAM_FOURCC`（全局）或 `CAM_LEFT_FOURCC` / `CAM_RIGHT_FOURCC` / `CAM_FRONT_FOURCC`（分相机）。
- 若本机 `spd-say` 不稳定，设置 `PLAY_SOUNDS=false`（录制脚本默认即为 false）。
- 若仅本地调试、不上传 Hub，可将 `DATASET_PUSH_TO_HUB=false`。
- 热键可通过环境变量覆盖：`INTERVENTION_TOGGLE_KEY`（介入开关）、`EPISODE_SUCCESS_KEY`（结束当前 episode 并标记成功）、`EPISODE_FAILURE_KEY`（结束当前 episode 并标记失败）。
- 如不希望触发全局左右方向键快捷逻辑，可设置：`LEROBOT_ENABLE_ARROW_HOTKEYS=false`（本仓库录制脚本默认即为 false）。

### 6.2 Finetune 录制（纯示教，建议只保留成功完整轨迹）

```bash
chmod +x scripts/teleop/run_bi_so_record_three_cam_ft.sh
export DATASET_REPO_ID=<HF_USERNAME_OR_ORG>/<DATASET_NAME>
export DATASET_SINGLE_TASK="bimanual pick and place"
export DATASET_NUM_EPISODES=50
export DATASET_EPISODE_TIME_S=35
export DATASET_RESET_TIME_S=20
export DATASET_PUSH_TO_HUB=false
export WAIT_FOR_EPISODE_START=true
export EPISODE_START_KEY=0
export EPISODE_END_KEY=1
export EPISODE_DISCARD_KEY=7
./scripts/teleop/run_bi_so_record_three_cam_ft.sh
```

说明：

- Finetune 脚本内部调用 `lerobot-record`（非 human-inloop 标注流），更适合构建干净示教数据集。
- 推荐将 RL/HIL 数据与 Finetune 数据分到不同 `DATASET_REPO_ID`，避免训练阶段语义混淆。
- 推荐直接使用 `scripts/teleop/run_bi_so_record_three_cam_rl.sh` 与 `scripts/teleop/run_bi_so_record_three_cam_ft.sh` 两套脚本，避免旧路径混用。

## 7. Replay 指定 episode（双臂回放）

```bash
set -a && source scripts/teleop/so101_bi_three_cam.env && set +a
chmod +x scripts/teleop/run_bi_so_replay_three_cam.sh
export DATASET_REPO_ID=<HF_USERNAME_OR_ORG>/<DATASET_NAME>
export DATASET_EPISODE=0
./scripts/teleop/run_bi_so_replay_three_cam.sh
```

说明：

- 脚本内部调用 `lerobot-replay`，按 `DATASET_EPISODE` 回放动作序列。
- 回放主要用关节动作，不依赖三路相机输入；但串口与机械臂需在线。
- 若数据集在本地自定义目录，可额外设置 `DATASET_ROOT=/path/to/local/datasets`。

## 稳定性

建议先执行 `scripts/teleop/check_bi_so_cameras.sh` 做设备与抓帧自检，再启动 teleop/record。

- 观察终端 `Teleop loop time` 是否长期平稳。
- 掉帧时优先降低 `CAM_FPS` 或分辨率，或把第三路相机插到另一 USB 控制器口。

