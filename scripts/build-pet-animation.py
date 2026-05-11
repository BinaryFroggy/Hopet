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

# 与 Sources/Hopet/Theme/DefaultTheme.swift hopiAnimations() 的 suffix 字典保持一致。
# 批量出 GIF 时按这里的 slug 精确遍历，而非 glob Resources/Themes/Hopi/seal-*：
# 一旦未来出现未挂载到 PetState 的孤儿目录，硬列清单可以避免误生成残留 GIF。
HOPI_STATE_SLUGS = [
    "idle",
    "thinking",
    "responding",
    "tool-use",
    "permission-prompt",
    "ask-user",
    "completed",
    "error-interrupted",
]


def _scale_centered(frame: Image.Image, scale: float) -> Image.Image:
    """把整帧等比缩放后居中放回 320×240 透明画布，画框尺寸保持不变。
    用 LANCZOS 重采样：seal-* sprite 已带柔边反走样，NEAREST 在非整数倍缩放下
    像素分布会不均匀。"""
    W, H = frame.size
    new_w = max(1, int(round(W * scale)))
    new_h = max(1, int(round(H * scale)))
    scaled = frame.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.paste(scaled, ((W - new_w) // 2, (H - new_h) // 2), scaled)
    return canvas


def slice_sheet(sheet: Path, out_dir: Path, content_scale: float) -> list[Image.Image]:
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
        if content_scale != 1.0:
            f = _scale_centered(f, content_scale)
        f.save(out_dir / f"{i:02d}.png")
        frames.append(f)
        bb = f.getbbox()
        if bb:
            l, t, r2, b = bb
            cxs.append((l + r2) / 2)
            cys.append((t + b) / 2)

    print(f"[ok] sliced {total} frames at {CELL_W}x{CELL_H} -> {out_dir.relative_to(ROOT)}")
    if content_scale != 1.0:
        print(f"     content scaled to {content_scale:g} centered on transparent canvas")
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


def rebuild_all_gifs(out_dir: Path, fps: float) -> None:
    """从 Resources/Themes/Hopi/seal-<slug>/ 现有 PNG 帧目录批量生成 GIF。
    跳过 sprite slicing —— 各状态的 PNG 帧（含 --scale 后处理结果）就是 GIF 的素材。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    for slug in HOPI_STATE_SLUGS:
        frame_dir = THEME_DIR / f"seal-{slug}"
        png_files = sorted(frame_dir.glob("*.png"))
        if not png_files:
            print(f"[skip] seal-{slug}: no PNG frames at {frame_dir.relative_to(ROOT)}")
            continue
        frames = [Image.open(p).convert("RGBA") for p in png_files]
        gif_path = out_dir / f"seal-{slug}.gif"
        build_gif(frames, gif_path, fps)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("state", nargs="?", help="PetState slug, e.g. idle / thinking / ask-user / permission-prompt")
    ap.add_argument("sheet", nargs="?", help="sprite sheet path (default: DevDocs/assets/seal-<state>-spritesheet.png)")
    ap.add_argument("--fps", type=float, default=8.0, help="frames per second (default: 8)")
    ap.add_argument(
        "--scale",
        type=float,
        default=1.0,
        help="等比缩放每帧内容，画框 320×240 保持不变、四周透明；用于让"
        " sprite 本体偏大的状态（如 seal-responding）跟其他状态视觉对齐。",
    )
    ap.add_argument(
        "--rebuild-gifs",
        metavar="OUT_DIR",
        help="跳过 sprite 切片，直接把 Hopi 主题已挂载的全部 PetState 对应的 PNG 帧"
        "目录批量打包为透明背景 GIF 到 OUT_DIR；用于一次性导出当前主题预览。",
    )
    args = ap.parse_args()

    if not 0 < args.scale <= 1:
        sys.exit(f"--scale must be in (0, 1]; got {args.scale}")

    if args.rebuild_gifs:
        rebuild_all_gifs(Path(args.rebuild_gifs).resolve(), args.fps)
        return

    if not args.state:
        ap.error("state is required (or pass --rebuild-gifs OUT_DIR)")

    slug = args.state
    sheet = Path(args.sheet) if args.sheet else ASSET_DIR / f"seal-{slug}-spritesheet.png"
    if not sheet.exists():
        sys.exit(f"sheet not found: {sheet}")

    out_dir = THEME_DIR / f"seal-{slug}"
    gif_path = ASSET_DIR / f"seal-{slug}.gif"

    frames = slice_sheet(sheet, out_dir, args.scale)
    build_gif(frames, gif_path, args.fps)


if __name__ == "__main__":
    main()
