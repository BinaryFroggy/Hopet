#!/usr/bin/env python3
"""把一张规则等距 sprite sheet 切成逐帧 PNG，并出一张透明背景 GIF 预览。

用法
    scripts/build-pet-animation.py <state> [sheet-path] [--fps N]

约定（与项目其他 PetState 动画保持一致；不规则源图请先在 GIMP / 设计工具里规整后再喂进来）
    - sprite sheet 必须 transparent PNG，cols=7，cell=320×240，整图 = (2240, rows×240)
    - rows ∈ {3, 4} 由图高自动推断（21 帧 / 28 帧）
    - 输出帧目录: Sources/Hopet/Resources/Themes/Hopi/seal-<state>/{00..NN}.png
    - 输出 GIF:   DevDocs/assets/seal-<state>.gif
    - state 既是 PetState 标识，也直接拼到资源/GIF 路径里 —— 不做 enum 校验，
      新增主题 / 实验状态时直接传任意 slug 也能跑。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("missing Pillow: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
THEME_DIR = ROOT / "Sources/Hopet/Resources/Themes/Hopi"
ASSET_DIR = ROOT / "DevDocs/assets"

COLS = 7
CELL_W, CELL_H = 320, 240
SENTINEL = (255, 0, 255)  # magenta；GIF 1-bit alpha 用的"透明色"哨兵


def slice_sheet(sheet: Path, out_dir: Path) -> list[Image.Image]:
    im = Image.open(sheet).convert("RGBA")
    W, H = im.size
    if W != CELL_W * COLS:
        sys.exit(f"sheet width {W} ≠ {CELL_W}*{COLS}={CELL_W*COLS}")
    if H % CELL_H != 0:
        sys.exit(f"sheet height {H} not divisible by {CELL_H}")
    rows = H // CELL_H
    total = COLS * rows

    if im.getextrema()[3] == (255, 255):
        print("[warn] sheet has no transparent pixels; output frames will retain the source background.")

    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.png"):
        stale.unlink()

    frames: list[Image.Image] = []
    cxs: list[float] = []
    cys: list[float] = []
    for i in range(total):
        c, r = i % COLS, i // COLS
        f = im.crop((c * CELL_W, r * CELL_H, (c + 1) * CELL_W, (r + 1) * CELL_H))
        f.save(out_dir / f"{i:02d}.png")
        frames.append(f)
        bb = f.getbbox()
        if bb:
            l, t, r2, b = bb
            cxs.append((l + r2) / 2)
            cys.append((t + b) / 2)

    print(f"[ok] sliced {total} frames at {CELL_W}x{CELL_H} -> {out_dir.relative_to(ROOT)}")
    if cxs:
        cx_span = max(cxs) - min(cxs)
        cy_span = max(cys) - min(cys)
        flag = "" if cx_span <= 8 and cy_span <= 30 else "  ← misalignment likely; check source art"
        print(f"     alignment: cx span={cx_span:.1f}px, cy span={cy_span:.1f}px{flag}")
    return frames


def build_gif(frames: list[Image.Image], gif_path: Path, fps: float) -> None:
    W, H = frames[0].size

    def composite_with_sentinel(fr: Image.Image) -> Image.Image:
        # GIF 只支持 1-bit alpha：alpha≥128 视为不透明，<128 涂成 sentinel。
        a = fr.split()[3].point(lambda x: 255 if x >= 128 else 0)
        rgb = fr.convert("RGB")
        bg = Image.new("RGB", fr.size, SENTINEL)
        return Image.composite(rgb, bg, a)

    masked = [composite_with_sentinel(f) for f in frames]

    # 全帧拼成纵向 mosaic 共享一个调色板，避免帧间调色板抖动。
    mosaic = Image.new("RGB", (W, H * len(masked)), SENTINEL)
    for i, m in enumerate(masked):
        mosaic.paste(m, (0, i * H))
    pal_img = mosaic.quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE)

    # 找 sentinel 在 palette 里最近的 index 当作 transparency。
    pal = pal_img.getpalette()
    sentinel_idx, best = 0, float("inf")
    for i in range(len(pal) // 3):
        r, g, b = pal[i * 3 : i * 3 + 3]
        d = (r - SENTINEL[0]) ** 2 + (g - SENTINEL[1]) ** 2 + (b - SENTINEL[2]) ** 2
        if d < best:
            best, sentinel_idx = d, i

    pframes = [m.quantize(palette=pal_img, dither=Image.NONE) for m in masked]
    duration_ms = int(round(1000 / max(fps, 1)))
    gif_path.parent.mkdir(parents=True, exist_ok=True)
    pframes[0].save(
        gif_path,
        save_all=True,
        append_images=pframes[1:],
        duration=duration_ms,
        loop=0,
        disposal=2,
        transparency=sentinel_idx,
        optimize=False,
    )
    print(f"[ok] gif -> {gif_path.relative_to(ROOT)} ({gif_path.stat().st_size // 1024} KB, {duration_ms}ms/frame)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("state", help="PetState slug, e.g. idle / thinking / ask-user / permission-prompt")
    ap.add_argument("sheet", nargs="?", help="sprite sheet path (default: DevDocs/assets/seal-<state>-spritesheet.png)")
    ap.add_argument("--fps", type=float, default=8.0, help="frames per second (default: 8)")
    args = ap.parse_args()

    slug = args.state
    sheet = Path(args.sheet) if args.sheet else ASSET_DIR / f"seal-{slug}-spritesheet.png"
    if not sheet.exists():
        sys.exit(f"sheet not found: {sheet}")

    out_dir = THEME_DIR / f"seal-{slug}"
    gif_path = ASSET_DIR / f"seal-{slug}.gif"

    frames = slice_sheet(sheet, out_dir)
    build_gif(frames, gif_path, args.fps)


if __name__ == "__main__":
    main()
