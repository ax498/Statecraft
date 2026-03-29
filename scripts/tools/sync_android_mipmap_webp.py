# -*- coding: utf-8 -*-
"""
在 Gradle 构建前：从 resources/pictures/icon.png 生成各 mipmap 的 webp。

- icon.webp：等比「包含」进 dim×dim（不拉伸变形），不足边用整图平均色填边，避免内容被裁到画外或圆角裁掉四角。
- icon_foreground / icon_background：前景同上；背景为整图平均色实心（闪屏/主题可能引用）。

若存在 mipmap-anydpi-v26/icon.xml，启动器会使用自适应双层 + 遮罩，易出现「一圈边」。
由 build.gradle 的 useLegacyLauncherIconOnly 任务在构建前删除该 xml，强制走 legacy icon.webp（显示效果接近电脑上的方形图标）。

用法：
  python scripts/tools/sync_android_mipmap_webp.py <项目根目录绝对路径>

依赖：pip install pillow
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageStat
except ImportError as e:
    print("缺少 Pillow，请执行: pip install pillow", file=sys.stderr)
    raise SystemExit(1) from e

# 与 Godot 4.6 platform/android/export/export_plugin.cpp 中 LAUNCHER_* 表一致
ADAPTIVE: list[tuple[str, int]] = [
    ("mipmap-xxxhdpi-v4", 432),
    ("mipmap-xxhdpi-v4", 324),
    ("mipmap-xhdpi-v4", 216),
    ("mipmap-hdpi-v4", 162),
    ("mipmap-mdpi-v4", 108),
    ("mipmap", 432),
]

MAIN_ICON: list[tuple[str, int]] = [
    ("mipmap-xxxhdpi-v4", 192),
    ("mipmap-xxhdpi-v4", 144),
    ("mipmap-xhdpi-v4", 96),
    ("mipmap-hdpi-v4", 72),
    ("mipmap-mdpi-v4", 48),
    ("mipmap", 192),
]


def _mean_rgb(img: Image.Image) -> tuple[int, int, int]:
    """整图均值，作自适应背景层纯色（与主图协调）。"""
    rgb = img.convert("RGB")
    stat = ImageStat.Stat(rgb)
    return (int(round(stat.mean[0])), int(round(stat.mean[1])), int(round(stat.mean[2])))


def _resize_contain_square(img: Image.Image, dim: int, pad_rgb: tuple[int, int, int]) -> Image.Image:
    """等比缩放，完整放入 dim×dim，居中；边条用 pad_rgb 填充（不拉伸原图，避免「超出」或圆角裁切关键内容）。"""
    w, h = img.size
    if w < 1 or h < 1:
        return Image.new("RGBA", (dim, dim), (*pad_rgb, 255))
    if w == dim and h == dim:
        return img.copy()
    scale = min(float(dim) / float(w), float(dim) / float(h))
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (dim, dim), (*pad_rgb, 255))
    ox = (dim - nw) // 2
    oy = (dim - nh) // 2
    out.paste(resized, (ox, oy), resized)
    return out


def main() -> None:
    if len(sys.argv) < 2:
        print("用法: python sync_android_mipmap_webp.py <项目根目录>", file=sys.stderr)
        raise SystemExit(2)
    root = Path(sys.argv[1]).resolve()
    res = root / "android" / "build" / "res"
    icon_src = root / "resources" / "pictures" / "icon.png"
    if not icon_src.is_file():
        print("缺少 icon.png:", icon_src, file=sys.stderr)
        raise SystemExit(1)

    master = Image.open(icon_src).convert("RGBA")
    br, bg, bb = _mean_rgb(master)

    for folder, dim in ADAPTIVE:
        d = res / folder
        d.mkdir(parents=True, exist_ok=True)
        fg = _resize_contain_square(master, dim, (br, bg, bb))
        bg_img = Image.new("RGBA", (dim, dim), (br, bg, bb, 255))
        fg.save(d / "icon_foreground.webp", "WEBP", lossless=True, method=6)
        bg_img.save(d / "icon_background.webp", "WEBP", lossless=True, method=6)
        print("写入", (d / "icon_foreground.webp").relative_to(root))
        print("写入", (d / "icon_background.webp").relative_to(root))

    for folder, dim in MAIN_ICON:
        d = res / folder
        d.mkdir(parents=True, exist_ok=True)
        out = _resize_contain_square(master, dim, (br, bg, bb))
        p = d / "icon.webp"
        out.save(p, "WEBP", lossless=True, method=6)
        print("写入", p.relative_to(root))

    print("sync_android_mipmap_webp: 完成（主图标 = 等比包含 + 平均色填边）。")


if __name__ == "__main__":
    main()
