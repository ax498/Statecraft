# -*- coding: utf-8 -*-
"""
从 resources/pictures/icon.png 生成 Android 自适应图标层（432×432）。
- 前景：按 alpha 内容裁切后，按「中心圆安全区」内接缩放（非正方形安全区），居中置于透明画布上。
- 背景：纯色，避免与前景共用同一张图导致叠层异常。
用法：在项目根目录执行  python scripts/tools/build_adaptive_icons.py

注意：Android 导出预设里请使用 res:// 路径指向上述 PNG。
若使用 uid://，导出时 ResourceLoader 可能解析失败，自适应前景会静默回退为「主图标」，
效果与未配置自适应层相同（大图被硬缩放到 432，桌面只像「中间一块」）。

Gradle 构建前会执行 scripts/tools/sync_android_mipmap_webp.py，用本 PNG 覆盖 android/build/res 下全部
icon_foreground/icon_background/icon.webp（需 pip install pillow），不依赖编辑器内加载是否成功。
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _read_chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    pos = 8
    chunks: list[tuple[bytes, bytes]] = []
    while pos < len(data):
        if pos + 8 > len(data):
            break
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        pos += 8
        cdata = data[pos : pos + length]
        pos += length + 4  # skip CRC
        chunks.append((ctype, cdata))
    return chunks


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png_rgba(path: Path) -> tuple[int, int, list[int]]:
    data = path.read_bytes()
    if data[:8] != PNG_SIG:
        raise ValueError("not a PNG")
    chunks = _read_chunks(data)
    ihdr = None
    idat_parts: list[bytes] = []
    for ctype, cdata in chunks:
        if ctype == b"IHDR":
            ihdr = cdata
        elif ctype == b"IDAT":
            idat_parts.append(cdata)
    if not ihdr or not idat_parts:
        raise ValueError("missing IHDR or IDAT")
    w, h = struct.unpack(">II", ihdr[:8])
    bd, ct, comp, filt, inter = ihdr[8], ihdr[9], ihdr[10], ihdr[11], ihdr[12]
    if bd != 8 or ct != 6 or inter != 0:
        raise ValueError(f"unsupported PNG: bd={bd} ct={ct} inter={inter}")
    raw = zlib.decompress(b"".join(idat_parts))
    bpp = 4
    stride = w * bpp
    out: list[int] = [0] * (w * h * 4)
    prev = bytearray(stride)
    i = 0
    o = 0
    for y in range(h):
        ftype = raw[i]
        i += 1
        row = bytearray(raw[i : i + stride])
        i += stride
        if ftype == 0:
            pass
        elif ftype == 1:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + left) & 0xFF
        elif ftype == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 0xFF
        elif ftype == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                up = prev[x]
                row[x] = (row[x] + ((left + up) // 2)) & 0xFF
        elif ftype == 4:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                up = prev[x]
                ul = prev[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + _paeth(left, up, ul)) & 0xFF
        else:
            raise ValueError(f"unknown filter {ftype}")
        prev = row
        for x in range(stride):
            out[o + x] = row[x]
        o += stride
    return w, h, out


def _bbox_rgba(w: int, h: int, px: list[int], alpha_threshold: int = 8) -> tuple[int, int, int, int]:
    min_x, min_y = w, h
    max_x, max_y = -1, -1
    for yy in range(h):
        row = yy * w * 4
        for xx in range(w):
            a = px[row + xx * 4 + 3]
            if a > alpha_threshold:
                if xx < min_x:
                    min_x = xx
                if yy < min_y:
                    min_y = yy
                if xx > max_x:
                    max_x = xx
                if yy > max_y:
                    max_y = yy
    if max_x < 0:
        return 0, 0, w, h
    return min_x, min_y, max_x + 1, max_y + 1


def _sample_bilinear(
    sw: int,
    sh: int,
    src: list[int],
    fx: float,
    fy: float,
) -> tuple[int, int, int, int]:
    if fx <= 0:
        x0 = 0
    elif fx >= sw - 1:
        x0 = sw - 2
    else:
        x0 = int(fx)
    if fy <= 0:
        y0 = 0
    elif fy >= sh - 1:
        y0 = sh - 2
    else:
        y0 = int(fy)
    tx = fx - x0
    ty = fy - y0
    o = (x0 + y0 * sw) * 4

    def p(ix: int, iy: int) -> tuple[int, int, int, int]:
        oo = (ix + iy * sw) * 4
        return src[oo], src[oo + 1], src[oo + 2], src[oo + 3]

    c00 = p(x0, y0)
    c10 = p(x0 + 1, y0)
    c01 = p(x0, y0 + 1)
    c11 = p(x0 + 1, y0 + 1)

    def lerp(a: float, b: float, t: float) -> float:
        return a + (b - a) * t

    r = int(
        lerp(
            lerp(c00[0], c10[0], tx),
            lerp(c01[0], c11[0], tx),
            ty,
        )
    )
    g = int(
        lerp(
            lerp(c00[1], c10[1], tx),
            lerp(c01[1], c11[1], tx),
            ty,
        )
    )
    b = int(
        lerp(
            lerp(c00[2], c10[2], tx),
            lerp(c01[2], c11[2], tx),
            ty,
        )
    )
    a = int(
        lerp(
            lerp(c00[3], c10[3], tx),
            lerp(c01[3], c11[3], tx),
            ty,
        )
    )
    return r, g, b, a


def _scale_rgba(
    sw: int,
    sh: int,
    src: list[int],
    dw: int,
    dh: int,
) -> list[int]:
    out: list[int] = [0] * (dw * dh * 4)
    sx = (sw - 1) / max(dw - 1, 1)
    sy = (sh - 1) / max(dh - 1, 1)
    for dy in range(dh):
        fy = dy * sy
        for dx in range(dw):
            fx = dx * sx
            r, g, b, a = _sample_bilinear(sw, sh, src, fx, fy)
            o = (dx + dy * dw) * 4
            out[o] = r
            out[o + 1] = g
            out[o + 2] = b
            out[o + 3] = a
    return out


def _write_png_rgba(path: Path, w: int, h: int, px: list[int]) -> None:
    bpp = 4
    stride = w * bpp
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        row_start = y * stride
        raw.extend(px[row_start : row_start + stride])
    compressed = zlib.compress(bytes(raw), 9)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)

    def chunk(t: bytes, d: bytes) -> bytes:
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    out = PNG_SIG + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.write_bytes(out)


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    src = root / "resources" / "pictures" / "icon.png"
    out_fg = root / "resources" / "pictures" / "icon_adaptive_fg.png"
    out_bg = root / "resources" / "pictures" / "icon_adaptive_bg.png"

    sw, sh, src_px = decode_png_rgba(src)
    bx0, by0, bx1, by1 = _bbox_rgba(sw, sh, src_px)
    cw, ch = bx1 - bx0, by1 - by0
    crop: list[int] = [0] * (cw * ch * 4)
    for yy in range(ch):
        sy = by0 + yy
        for xx in range(cw):
            sx = bx0 + xx
            si = (sx + sy * sw) * 4
            di = (xx + yy * cw) * 4
            crop[di : di + 4] = src_px[si : si + 4]

    canvas = 432
    # 自适应图标「安全区」约为直径 = 画布 66% 的中心圆。主图外接圆半径不得超过该安全圆半径，
    # 否则（例如长边占画布 90%）会画出安全区，启动器圆角/圆形遮罩会裁掉四周 → 「只剩中间一块」。
    # 这里用整图外接圆贴齐安全圆，并略缩小 2% 避免贴边锯齿；外圈用下面铺底色填充，减轻白边观感。
    safe_diameter = float(canvas) * 0.66
    safe_radius = safe_diameter * 0.5
    half_diag = 0.5 * ((cw * cw + ch * ch) ** 0.5)
    inset = 0.98
    scale = (safe_radius * inset) / half_diag if half_diag > 1e-6 else 1.0
    nw = max(1, int(round(cw * scale)))
    nh = max(1, int(round(ch * scale)))
    scaled = _scale_rgba(cw, ch, crop, nw, nh)

    def _lum(r: int, g: int, b: int) -> int:
        return (299 * r + 587 * g + 114 * b) // 1000

    def _scaled_corner_patches_avg_rgb(px: list[int], w: int, h: int) -> tuple[int, int, int]:
        """圆与方之间的铺底应对齐「四角纸色」。整圈边缘平均会混入上下边的墨色 → 黑边；
        仅用原图四角又易偏亮 → 白边。这里对缩放图四角各取一小块再平均。"""
        if w < 2 or h < 2:
            return (216, 202, 184)
        k = max(6, min(w, h) // 14)
        k = min(k, w // 2, h // 2)
        r_acc = g_acc = b_acc = 0
        cnt = 0
        corners_xy = [(0, 0), (w - k, 0), (0, h - k), (w - k, h - k)]
        for x0, y0 in corners_xy:
            for yy in range(y0, min(y0 + k, h)):
                for xx in range(x0, min(x0 + k, w)):
                    o = (xx + yy * w) * 4
                    if px[o + 3] < 8:
                        continue
                    r_acc += px[o]
                    g_acc += px[o + 1]
                    b_acc += px[o + 2]
                    cnt += 1
        if cnt == 0:
            return (216, 202, 184)
        return (r_acc // cnt, g_acc // cnt, b_acc // cnt)

    def _crop_four_corners_avg_rgb() -> tuple[int, int, int]:
        pts = [(0, 0), (cw - 1, 0), (0, ch - 1), (cw - 1, ch - 1)]
        r_acc = g_acc = b_acc = 0
        for cx, cy in pts:
            o = (cx + cy * cw) * 4
            r_acc += crop[o]
            g_acc += crop[o + 1]
            b_acc += crop[o + 2]
        n = len(pts)
        return (r_acc // n, g_acc // n, b_acc // n)

    def _paper_fill_rgb() -> tuple[int, int, int]:
        a = _scaled_corner_patches_avg_rgb(scaled, nw, nh)
        b = _crop_four_corners_avg_rgb()
        # 以缩放四角块为主（纸色），原图四角为辅，缓和过亮/过暗
        r = (65 * a[0] + 35 * b[0]) // 100
        g = (65 * a[1] + 35 * b[1]) // 100
        bl = (65 * a[2] + 35 * b[2]) // 100
        warm = (216, 202, 184)
        lu = _lum(r, g, bl)
        if lu < 75:
            r = (r + warm[0]) // 2
            g = (g + warm[1]) // 2
            bl = (bl + warm[2]) // 2
        elif lu > 228:
            r = (7 * r + 3 * warm[0]) // 10
            g = (7 * g + 3 * warm[1]) // 10
            bl = (7 * bl + 3 * warm[2]) // 10
        return (r, g, bl)

    bg_r, bg_g, bg_b = _paper_fill_rgb()

    # 前景：先整幅铺不透明底色（与自适应背景层同色），再叠图案。
    # 若仅用透明底 + 中间一块图，圆角遮罩下「圆与方形」之间无像素 → 会透出背景层，看起来像粗边框（白/深色框）。
    fg: list[int] = [0] * (canvas * canvas * 4)
    for i in range(canvas * canvas):
        o = i * 4
        fg[o] = bg_r
        fg[o + 1] = bg_g
        fg[o + 2] = bg_b
        fg[o + 3] = 255

    ox = (canvas - nw) // 2
    oy = (canvas - nh) // 2
    for yy in range(nh):
        for xx in range(nw):
            si = (xx + yy * nw) * 4
            sr, sg, sb, sa = scaled[si], scaled[si + 1], scaled[si + 2], scaled[si + 3]
            di = ((ox + xx) + (oy + yy) * canvas) * 4
            if sa >= 255:
                fg[di] = sr
                fg[di + 1] = sg
                fg[di + 2] = sb
                fg[di + 3] = 255
            elif sa <= 0:
                continue
            else:
                inv = 255 - sa
                dr, dg, db = fg[di], fg[di + 1], fg[di + 2]
                fg[di] = (sr * sa + dr * inv) // 255
                fg[di + 1] = (sg * sa + dg * inv) // 255
                fg[di + 2] = (sb * sa + db * inv) // 255
                fg[di + 3] = 255
    bg: list[int] = []
    for _ in range(canvas * canvas):
        bg.extend([bg_r, bg_g, bg_b, 255])

    _write_png_rgba(out_fg, canvas, canvas, fg)
    _write_png_rgba(out_bg, canvas, canvas, bg)
    print(f"源图: {sw}x{sh}, 内容 bbox: ({bx0},{by0})-({bx1},{by1}) -> {cw}x{ch}")
    print(f"前景缩放: {nw}x{nh} @ offset ({ox},{oy})")
    print(f"已写入: {out_fg.relative_to(root)}")
    print(f"已写入: {out_bg.relative_to(root)}")


if __name__ == "__main__":
    main()
