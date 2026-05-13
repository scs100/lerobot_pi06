# PI05 直接 conda 训练（不走 runtime/lock）

PROJECT_ROOT=/media/jushen/stone-shi/code/mylong/lerobot_pi06
cd "${PROJECT_ROOT}" || exit 1

# 保持模型和缓存在 /media（沿用已有预训练组件）
SHARED_HF_HOME=/media/jushen/stone-shi/lerobot_pi06/hf_home
OFFLINE_PRETRAINED_MODEL_PATH=/media/jushen/stone-shi/lerobot_pi06/models/lerobot_pi05_base
SHARED_TOKENIZER_DIR=/media/jushen/stone-shi/lerobot_pi06/models/google_paligemma_3b_pt_224_tokenizer

# 1) 一次性准备容器内 conda 环境（离线 PI05 + OnlineRL 共用）
conda create -y -n lerobotpi6 python=3.10
http_proxy="http://192.168.32.28:18000" https_proxy="http://192.168.32.28:18000" \
PIP_INDEX_URL="https://pypi.org/simple" \
conda run -n lerobotpi6 python -m pip install -e ".[pi,grpcio-dep]" --no-build-isolation

# 2) 每次训练前激活 conda 环境
source /opt/conda/etc/profile.d/conda.sh
conda activate lerobotpi6

# 3) 训练（直接调用 trainpi05.sh，不使用 env_trainpi05.sh）
cd /media/jushen/stone-shi/code/mylong/lerobot_pi06 
source /opt/conda/etc/profile.d/conda.sh
conda activate lerobotpi6
export WANDB_PROJECT="put_the_phone_stand_into_the_shipping_box0509_2208_6gpus_bf16_bs64"
export WANDB_API_KEY="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"
SHARED_HF_HOME=/media/jushen/stone-shi/lerobot_pi06/hf_home
OFFLINE_PRETRAINED_MODEL_PATH=/media/jushen/stone-shi/lerobot_pi06/models/lerobot_pi05_base
SHARED_TOKENIZER_DIR=/media/jushen/stone-shi/lerobot_pi06/models/google_paligemma_3b_pt_224_tokenizer
# 说明：--offline 时会从 OFFLINE_PRETRAINED_MODEL_PATH 读取本地预训练模型，不走联网下载。
bash scripts/training/trainpi05.sh train \
  --proxy \
  --hf-home "${SHARED_HF_HOME}" \
  --pretrained-path "${OFFLINE_PRETRAINED_MODEL_PATH}" \
  --offline \
  --dataset-root /media/jushen/stone-shi/lerobot_v30/put_the_phone_stand_into_the_shipping_box0509_2208 \
  --output-root /media/jushen/stone-shi/lerobot_pi06/checkpoints/lerobotpi06 \
  --num-processes 6 \
  --cuda-visible-devices 0,1,2,3,4,5 \
  --save-freq 5000 \
  --log-freq 5 \
  --wandb-enable true \
  --wandb-project "${WANDB_PROJECT}" \
  --wandb-api-key "${WANDB_API_KEY}" \
  --mixed-precision bf16 \
  --batch-size 64 \
  --steps 30000 \
  --compile-model false \
  --run-tag 8gpus_bf16_bs64


#分布式训练
cd /media/jushen/stone-shi/code/mylong/lerobot_pi06 
source /opt/conda/etc/profile.d/conda.sh
conda activate lerobotpi6
export WANDB_PROJECT="put_the_phone_stand_into_the_shipping_box0509_2208_8gpus_bf16_bs64"
export WANDB_API_KEY="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"
SHARED_HF_HOME=/media/jushen/stone-shi/lerobot_pi06/hf_home
OFFLINE_PRETRAINED_MODEL_PATH=/media/jushen/stone-shi/lerobot_pi06/models/lerobot_pi05_base
SHARED_TOKENIZER_DIR=/media/jushen/stone-shi/lerobot_pi06/models/google_paligemma_3b_pt_224_tokenizer
# 说明：--offline 时会从 OFFLINE_PRETRAINED_MODEL_PATH 读取本地预训练模型，不走联网下载。
bash scripts/training/trainpi05.sh train \
  --proxy \
  --hf-home "${SHARED_HF_HOME}" \
  --pretrained-path "${OFFLINE_PRETRAINED_MODEL_PATH}" \
  --offline \
  --dataset-root /media/jushen/stone-shi/lerobot_v30/put_the_phone_stand_into_the_shipping_box0509_2208 \
  --output-root /media/jushen/stone-shi/lerobot_pi06/checkpoints/lerobotpi06 \
  --num-processes 4 \
  --cuda-visible-devices 0,1,2,3 \
  --save-freq 5000 \
  --log-freq 100 \
  --wandb-enable true \
  --wandb-project "${WANDB_PROJECT}" \
  --wandb-api-key "${WANDB_API_KEY}" \
  --mixed-precision bf16 \
  --batch-size 64 \
  --steps 30000 \
  --compile-model false \
  --run-tag 4gpus_bf16_bs64


# 4) PI05 + OnlineRL 启动（同一 lerobotpi6 conda 环境）
# 说明：
# - learner / actor 必须使用同一个 --config-path 与 --output-dir
# - learner 默认 --resume false，若 output-dir 非空会拒绝启动（防止覆盖）
# - 建议先跑 check 和小步 smoke，再扩大到正式 online-steps

cd /media/jushen/stone-shi/code/mylong/lerobot_pi06
source /opt/conda/etc/profile.d/conda.sh
conda activate lerobotpi6
export WANDB_PROJECT="put_the_phone_stand_into_the_shipping_box0509_2208_online_rl"
export WANDB_API_KEY="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"
SHARED_HF_HOME=/media/jushen/stone-shi/lerobot_pi06/hf_home
OFFLINE_PRETRAINED_MODEL_PATH=/media/jushen/stone-shi/lerobot_pi06/models/lerobot_pi05_base
ONLINE_RL_OUTPUT=/media/jushen/stone-shi/lerobot_pi06/checkpoints/online_rl/2026-05-12_pi05_online_rl_smoke
ONLINE_RL_CONFIG=/path/to/train_config_hilserl_so100.json
DATASET_ROOT=/media/jushen/stone-shi/lerobot_v30/put_the_phone_stand_into_the_shipping_box0509_2208

# 4.1 先做 online 依赖/环境自检
bash scripts/training/trainpi05_online_rl.sh check \
  --proxy \
  --hf-home "${SHARED_HF_HOME}" \
  --policy-pretrained-path "${OFFLINE_PRETRAINED_MODEL_PATH}" \
  --offline

# 4.2 终端A：启动 learner（先用小步 smoke 参数）
bash scripts/training/trainpi05_online_rl.sh learner \
  --proxy \
  --hf-home "${SHARED_HF_HOME}" \
  --policy-pretrained-path "${OFFLINE_PRETRAINED_MODEL_PATH}" \
  --offline \
  --config-path "${ONLINE_RL_CONFIG}" \
  --output-dir "${ONLINE_RL_OUTPUT}" \
  --dataset-root "${DATASET_ROOT}" \
  --device cuda \
  --storage-device cpu \
  --online-steps 500 \
  --online-step-before-learning 64 \
  --batch-size 32 \
  --mini-batch-size 32 \
  --update-epochs 2 \
  --save-freq 200 \
  --log-freq 10 \
  --wandb-enable true \
  --wandb-project "${WANDB_PROJECT}" \
  --wandb-api-key "${WANDB_API_KEY}"

# 4.3 终端B：启动 actor（与 learner 保持同 config/output）
bash scripts/training/trainpi05_online_rl.sh actor \
  --proxy \
  --hf-home "${SHARED_HF_HOME}" \
  --policy-pretrained-path "${OFFLINE_PRETRAINED_MODEL_PATH}" \
  --offline \
  --config-path "${ONLINE_RL_CONFIG}" \
  --output-dir "${ONLINE_RL_OUTPUT}" \
  --dataset-root "${DATASET_ROOT}" \
  --device cuda \
  --storage-device cpu \
  --online-steps 500 \
  --online-step-before-learning 64 \
  --batch-size 32 \
  --mini-batch-size 32 \
  --update-epochs 2 \
  --save-freq 200 \
  --log-freq 10 \
  --wandb-enable true \
  --wandb-project "${WANDB_PROJECT}" \
  --wandb-api-key "${WANDB_API_KEY}"