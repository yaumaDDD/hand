# -*- coding: utf-8 -*-
"""Minimal VTF reader/writer used to shrink the oversized glove textures.

Reads the top mip of DXT1 / DXT5 / RGBA8888 / BGRA8888 / BGR888 / RGB888
textures (VTF 7.0 - 7.5) and writes DXT5 or DXT1 VTF 7.2 files with a full
mip chain. Needs numpy; writing additionally needs the "etcpak" package.
"""
import struct
import numpy as np

FMT_RGBA8888, FMT_ABGR8888, FMT_RGB888, FMT_BGR888 = 0, 1, 2, 3
FMT_ARGB8888, FMT_BGRA8888, FMT_DXT1, FMT_DXT3, FMT_DXT5 = 11, 12, 13, 14, 15
FMT_NAMES = {0: 'RGBA8888', 1: 'ABGR8888', 2: 'RGB888', 3: 'BGR888', 11: 'ARGB8888', 12: 'BGRA8888',
             13: 'DXT1', 14: 'DXT3', 15: 'DXT5', -1: 'NONE'}

FLAG_NOMIP, FLAG_NOLOD = 0x100, 0x200
FLAG_ONEBITALPHA, FLAG_EIGHTBITALPHA = 0x1000, 0x2000


def _mip_bytes(fmt, w, h):
    if fmt in (FMT_DXT1,):
        return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 8
    if fmt in (FMT_DXT3, FMT_DXT5):
        return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 16
    if fmt in (FMT_RGBA8888, FMT_ABGR8888, FMT_ARGB8888, FMT_BGRA8888):
        return w * h * 4
    if fmt in (FMT_RGB888, FMT_BGR888):
        return w * h * 3
    raise ValueError('unsupported VTF format %r' % fmt)


def read_header(buf):
    sig, vmaj, vmin, hsize = struct.unpack_from('<4sIII', buf, 0)
    if sig != b'VTF\0':
        raise ValueError('not a VTF file')
    w, h, flags, frames, first = struct.unpack_from('<HHIHH', buf, 16)
    refl = struct.unpack_from('<3f', buf, 32)
    bump, fmt, mips, lofmt, low, loh = struct.unpack_from('<fiBiBB', buf, 48)
    depth = struct.unpack_from('<H', buf, 63)[0] if vmin >= 2 else 1
    hdr = dict(version=(vmaj, vmin), header_size=hsize, width=w, height=h, flags=flags, frames=frames,
               first_frame=first, reflectivity=refl, bump_scale=bump, format=fmt, mips=mips,
               low_format=lofmt, low_width=low, low_height=loh, depth=max(1, depth))
    hdr['resources'] = {}
    if vmin >= 3:
        nres = struct.unpack_from('<I', buf, 68)[0]
        for i in range(nres):
            tag, rflags, off = struct.unpack_from('<3sBI', buf, 80 + i * 8)
            hdr['resources'][tag] = (rflags, off)
    return hdr


def _dxt_colors(blocks):
    """blocks: (n, 8) uint8 colour block -> (n, 16, 3) uint8, plus the c0 > c1 flag"""
    c0 = blocks[:, 0].astype(np.uint32) | (blocks[:, 1].astype(np.uint32) << 8)
    c1 = blocks[:, 2].astype(np.uint32) | (blocks[:, 3].astype(np.uint32) << 8)
    bits = (blocks[:, 4].astype(np.uint32) | (blocks[:, 5].astype(np.uint32) << 8) |
            (blocks[:, 6].astype(np.uint32) << 16) | (blocks[:, 7].astype(np.uint32) << 24))

    def expand(c):
        r = (c >> 11) & 31
        g = (c >> 5) & 63
        b = c & 31
        return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], axis=1).astype(np.int32)

    e0, e1 = expand(c0), expand(c1)
    pal = np.empty((len(blocks), 4, 3), np.int32)
    pal[:, 0], pal[:, 1] = e0, e1
    pal[:, 2] = (2 * e0 + e1) // 3
    pal[:, 3] = (e0 + 2 * e1) // 3
    idx = np.stack([(bits >> (2 * i)) & 3 for i in range(16)], axis=1)
    return pal, idx, c0 > c1, e0, e1


def _unblock(px, bw, bh, w, h):
    """px: (bh*bw, 16, C) -> (h, w, C)"""
    c = px.shape[2]
    img = px.reshape(bh, bw, 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(bh * 4, bw * 4, c)
    return img[:h, :w]


def decode_dxt1(data, w, h):
    bw, bh = max(1, (w + 3) // 4), max(1, (h + 3) // 4)
    blocks = np.frombuffer(data, np.uint8, bw * bh * 8).reshape(-1, 8)
    pal, idx, opaque, e0, e1 = _dxt_colors(blocks)
    alpha = np.full((len(blocks), 4), 255, np.int32)
    t = ~opaque
    pal[t, 2] = (e0[t] + e1[t]) // 2
    pal[t, 3] = 0
    alpha[t, 3] = 0
    rgb = np.take_along_axis(pal, idx[:, :, None], axis=1)
    a = np.take_along_axis(alpha, idx, axis=1)[:, :, None]
    return _unblock(np.concatenate([rgb, a], axis=2).astype(np.uint8), bw, bh, w, h)


def decode_dxt5(data, w, h):
    bw, bh = max(1, (w + 3) // 4), max(1, (h + 3) // 4)
    blocks = np.frombuffer(data, np.uint8, bw * bh * 16).reshape(-1, 16)
    pal, idx, _, _, _ = _dxt_colors(blocks[:, 8:])
    rgb = np.take_along_axis(pal, idx[:, :, None], axis=1)
    a0 = blocks[:, 0].astype(np.int32)
    a1 = blocks[:, 1].astype(np.int32)
    abits = np.zeros(len(blocks), np.uint64)
    for i in range(6):
        abits |= blocks[:, 2 + i].astype(np.uint64) << np.uint64(8 * i)
    apal = np.empty((len(blocks), 8), np.int32)
    apal[:, 0], apal[:, 1] = a0, a1
    gt = a0 > a1
    for i in range(1, 7):
        apal[:, i + 1] = np.where(gt, ((7 - i) * a0 + i * a1) // 7, 0)
    for i in range(1, 5):
        v = ((5 - i) * a0 + i * a1) // 5
        apal[:, i + 1] = np.where(gt, apal[:, i + 1], v)
    apal[:, 6] = np.where(gt, apal[:, 6], 0)
    apal[:, 7] = np.where(gt, apal[:, 7], 255)
    aidx = np.stack([((abits >> np.uint64(3 * i)) & np.uint64(7)).astype(np.int64) for i in range(16)], axis=1)
    a = np.take_along_axis(apal, aidx, axis=1)[:, :, None]
    return _unblock(np.concatenate([rgb, a], axis=2).astype(np.uint8), bw, bh, w, h)


def read_top_mip(path):
    """returns (header, HxWx4 uint8 RGBA array of the largest mip of frame 0)"""
    buf = open(path, 'rb').read()
    hdr = read_header(buf)
    fmt, w, h = hdr['format'], hdr['width'], hdr['height']
    if hdr['frames'] != 1 or hdr['depth'] != 1:
        raise ValueError('animated / volume textures are not supported')
    top = _mip_bytes(fmt, w, h)
    # the largest mip is always stored last, so it simply sits at the end of the image data
    hires = hdr['resources'].get(b'\x30\0\0')
    if hires is not None:
        total = sum(_mip_bytes(fmt, max(1, w >> m), max(1, h >> m)) for m in range(hdr['mips']))
        off = hires[1] + total - top
    else:
        off = len(buf) - top
    data = buf[off:off + top]
    if len(data) != top:
        raise ValueError('truncated VTF')
    if fmt == FMT_DXT5:
        img = decode_dxt5(data, w, h)
    elif fmt == FMT_DXT1:
        img = decode_dxt1(data, w, h)
    else:
        raw = np.frombuffer(data, np.uint8)
        if fmt == FMT_RGBA8888:
            img = raw.reshape(h, w, 4)
        elif fmt == FMT_BGRA8888:
            img = raw.reshape(h, w, 4)[:, :, [2, 1, 0, 3]]
        elif fmt == FMT_ABGR8888:
            img = raw.reshape(h, w, 4)[:, :, [3, 2, 1, 0]]
        elif fmt == FMT_ARGB8888:
            img = raw.reshape(h, w, 4)[:, :, [1, 2, 3, 0]]
        elif fmt in (FMT_RGB888, FMT_BGR888):
            rgb = raw.reshape(h, w, 3)
            if fmt == FMT_BGR888:
                rgb = rgb[:, :, ::-1]
            img = np.concatenate([rgb, np.full((h, w, 1), 255, np.uint8)], axis=2)
        else:
            raise ValueError('unsupported VTF format %r' % fmt)
    return hdr, np.ascontiguousarray(img)


def _halve(img, fx, fy):
    """box filter by integer factors (float32 in, float32 out)"""
    h, w, c = img.shape
    return img.reshape(h // fy, fy, w // fx, fx, c).mean(axis=(1, 3))


def _renormalize(img):
    """img float32 0..255 RGBA holding a tangent normal in RGB"""
    n = img[:, :, :3] / 127.5 - 1.0
    ln = np.sqrt((n * n).sum(axis=2, keepdims=True))
    n = np.where(ln > 1e-4, n / np.maximum(ln, 1e-4), np.array([0.0, 0.0, 1.0], np.float32))
    out = img.copy()
    out[:, :, :3] = (n + 1.0) * 127.5
    return out


def build_mips(img, size, normal=False):
    """img uint8 RGBA -> list of float32 mips, largest first, starting at (size x size)"""
    cur = img.astype(np.float32)
    h, w = cur.shape[:2]
    if w > size or h > size:
        f = max(w // size, h // size)
        if w % f or h % f:
            raise ValueError('cannot box-filter %dx%d down to %d' % (w, h, size))
        cur = _halve(cur, f, f)
    mips = []
    while True:
        if normal:
            cur = _renormalize(cur)
        mips.append(cur)
        h, w = cur.shape[:2]
        if w == 1 and h == 1:
            break
        cur = _halve(cur, 2 if w > 1 else 1, 2 if h > 1 else 1)
    return mips


def _to_bytes(mip):
    """float mip -> uint8 RGBA padded to a multiple of 4 (edge replicated), with its block size"""
    a = np.clip(np.rint(mip), 0, 255).astype(np.uint8)
    h, w = a.shape[:2]
    ph, pw = (4 - h % 4) % 4, (4 - w % 4) % 4
    if ph or pw:
        a = np.pad(a, ((0, ph), (0, pw), (0, 0)), mode='edge')
    return np.ascontiguousarray(a)


def write_vtf(path, mips, fmt=FMT_DXT5, flags=FLAG_EIGHTBITALPHA, bump_scale=1.0):
    """mips: list of float32 RGBA arrays, largest first"""
    import etcpak
    enc = etcpak.compress_bc3 if fmt == FMT_DXT5 else etcpak.compress_bc1
    w, h = mips[0].shape[1], mips[0].shape[0]
    # 16x16 (or smaller) DXT1 thumbnail
    thumb = next((m for m in mips if m.shape[0] <= 16 and m.shape[1] <= 16), mips[-1])
    tb = _to_bytes(thumb)
    thumb_data = etcpak.compress_bc1(tb.tobytes(), tb.shape[1], tb.shape[0])
    lin = (mips[0][:, :, :3] / 255.0) ** 2.2
    refl = [float(x) for x in lin.reshape(-1, 3).mean(axis=0)]
    hdr = bytearray(80)
    struct.pack_into('<4sIII', hdr, 0, b'VTF\0', 7, 2, 80)
    struct.pack_into('<HHIHH', hdr, 16, w, h, flags, 1, 0)
    struct.pack_into('<3f', hdr, 32, *refl)
    struct.pack_into('<fiBiBB', hdr, 48, bump_scale, fmt, len(mips), FMT_DXT1, thumb.shape[1], thumb.shape[0])
    struct.pack_into('<H', hdr, 63, 1)
    with open(path, 'wb') as f:
        f.write(hdr)
        f.write(thumb_data)
        for m in reversed(mips):  # smallest mip first
            b = _to_bytes(m)
            f.write(enc(b.tobytes(), b.shape[1], b.shape[0]))
