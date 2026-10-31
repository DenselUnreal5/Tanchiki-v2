"""Scale a lightning reel clip to Shorts 1080×1920."""
from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np


def scale_vertical(
    frame: np.ndarray,
    w: int = 1080,
    h: int = 1920,
    zoom: float = 1.72,
    cx: float = 0.50,
    cy: float = 0.46,
) -> np.ndarray:
    ih, iw = frame.shape[:2]
    zoom = max(1.0, zoom)
    cw = max(2, int(iw / zoom))
    ch = max(2, int(ih / zoom))
    if cw / ch > w / h:
        cw = max(2, int(ch * w / h))
    else:
        ch = max(2, int(cw * h / w))
    x0 = int(iw * cx - cw / 2)
    y0 = int(ih * cy - ch / 2)
    x0 = max(0, min(iw - cw, x0))
    y0 = max(0, min(ih - ch, y0))
    crop = frame[y0 : y0 + ch, x0 : x0 + cw]
    return cv2.resize(crop, (w, h), interpolation=cv2.INTER_NEAREST)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--start", type=int, default=24)
    p.add_argument("--frames", type=int, default=-1)
    p.add_argument("--zoom", type=float, default=1.72)
    args = p.parse_args()
    cap = cv2.VideoCapture(args.src)
    if not cap.isOpened():
        raise SystemExit(f"cannot open {args.src}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    if not frames:
        raise SystemExit("no frames")
    start = max(0, min(args.start, len(frames) - 1))
    length = len(frames) - start if args.frames < 0 else args.frames
    length = max(1, min(length, len(frames) - start))
    out_path = Path(args.dst)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(str(out_path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (1080, 1920))
    preview = scale_vertical(frames[start + length // 2], zoom=args.zoom)
    cv2.imwrite(str(out_path.with_suffix(".png")), preview)
    for i in range(start, start + length):
        writer.write(scale_vertical(frames[i], zoom=args.zoom))
    writer.release()
    print(f"frames={len(frames)} fps={fps:.2f} keep={start}:{start + length} ({length / fps:.2f}s)")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
