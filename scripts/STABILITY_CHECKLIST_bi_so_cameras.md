# 双臂三相机稳定性验收（3–5 分钟）

在 **`DISPLAY_DATA=true`** 且已安装 [Rerun Viewer](https://rerun.io/docs/getting-started/installing-viewer)（或 `pip install rerun-sdk` 后确保 `rerun` 在 `PATH`）时：

1. **三路画面**：Rerun 中 `observation.*` 图像实体是否持续刷新、无长时间冻结。
2. **循环频率**：终端 `Teleop loop time` 是否无周期性尖峰（例如长期稳定在目标附近）。
3. **USB**：若掉帧或断流，换 USB 口（不同 root hub）、降低 `CAM_FPS`（如 20）或分辨率。

无图形界面 / 无 Rerun 时先用：

```bash
DISPLAY_DATA=false FRONT_ONLY=1 ./scripts/run_bi_so_teleop_three_cam.sh
```

验证机械臂与相机采集链路，再安装 Viewer 打开可视化。
