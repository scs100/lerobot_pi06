#!/usr/bin/env python3
"""Open each V4L path with OpenCV; try 640x480@30 and report success (no v4l2-ctl required)."""
from __future__ import annotations

import sys
import time

try:
    import cv2
except ImportError as e:
    print("Install opencv in your env (e.g. conda env lerobot-pi06):", e)
    sys.exit(1)


def probe(path: str, width: int = 640, height: int = 480, fps: int = 30) -> None:
    cap = cv2.VideoCapture(path, cv2.CAP_V4L2)
    if not cap.isOpened():
        print(f"FAIL open: {path}")
        return
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    cap.set(cv2.CAP_PROP_FPS, fps)
    aw = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    ah = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    t0 = time.perf_counter()
    ok, frame = cap.read()
    dt_ms = (time.perf_counter() - t0) * 1e3
    cap.release()
    if ok and frame is not None:
        print(
            f"OK {path}  shape={frame.shape}  first_frame_ms={dt_ms:.1f}  "
            f"requested {width}x{height}@{fps}  driver_reported {aw}x{ah}"
        )
    else:
        print(f"FAIL read frame: {path}  (requested {width}x{height}@{fps})")


def main() -> None:
    paths = [p for p in sys.argv[1:] if p.strip()]
    if not paths:
        print("Usage: probe_v4l_opencv.py <device> [device ...]")
        sys.exit(2)
    for p in paths:
        probe(p)


if __name__ == "__main__":
    main()
