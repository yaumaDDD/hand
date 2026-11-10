# -*- coding: utf-8 -*-
"""Minimal VTF reader/writer used to shrink the oversized glove textures.

Reads the top mip of DXT1 / DXT5 / RGBA8888 / BGRA8888 / BGR888 / RGB888
textures (VTF 7.0 - 7.5) and writes DXT5 or DXT1 VTF 7.2 files with a full
mip chain. Needs numpy; writing additionally needs the "etcpak" package.

For make_skin.py it can also change a part of a DXT5 texture and leave the
rest of the file exactly as it is (patch_dxt5), and store the colours of a
DXT5 texture as DXT1 without compressing them again (dxt5_to_dxt1).
"""
import struct
import numpy as np

FMT_RGBA8888, FMT_ABGR8888, FMT_RGB888, FMT_BGR888 = 0, 1, 2, 3
FMT_ARGB8888, FMT_BGRA8888, FMT_DXT1, FMT_DXT3, FMT_DXT5 = 11, 12, 13, 14, 15
FMT_NAMES = {0: 'RGBA8888', 1: 'ABGR8888', 2: 'RGB888', 3: 'BGR888', 11: 'ARGB8888', 12: 'BGRA8888',
             13: 'DXT1', 14: 'DXT3', 15: 'DXT5', -1: 'NONE'}

FLAG_NORMAL = 0x80
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


def mip_bytes(fmt, w, h):
    """size of one mip in the file"""
    return _mip_bytes(fmt, w, h)


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
    with open(path, 'rb') as f:
        return decode_top_mip(f.read())


def mip_table(buf):
    """(header, [(offset, width, height), ...]) for the mips of a texture, the largest one first"""
    hdr = read_header(buf)
    fmt, w, h = hdr['format'], hdr['width'], hdr['height']
    if hdr['frames'] != 1 or hdr['depth'] != 1:
        raise ValueError('animated / volume textures are not supported')
    sizes = [(max(1, w >> m), max(1, h >> m)) for m in range(hdr['mips'])]
    total = sum(_mip_bytes(fmt, mw, mh) for mw, mh in sizes)
    hires = hdr['resources'].get(b'\x30\0\0')
    # without a resource list the image data simply sits at the end of the file
    off = hires[1] if hires is not None else len(buf) - total
    if off < 0 or off + total > len(buf):
        raise ValueError('truncated VTF')
    table = []
    for mw, mh in reversed(sizes):  # the smallest mip is stored first
        table.append((off, mw, mh))
        off += _mip_bytes(fmt, mw, mh)
    return hdr, table[::-1]


def decode_mip(buf, fmt, off, w, h):
    """one mip as a HxWx4 uint8 RGBA array"""
    data = bytes(buf[off:off + _mip_bytes(fmt, w, h)])
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
    return np.ascontiguousarray(img)


def decode_top_mip(buf):
    """the same as read_top_mip for the content of a VTF file"""
    hdr, table = mip_table(buf)
    return hdr, decode_mip(buf, hdr['format'], *table[0])


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
    # 16x16 (or smaller) DXT1 thumbnail
    thumb = next((m for m in mips if m.shape[0] <= 16 and m.shape[1] <= 16), mips[-1])
    tb = _to_bytes(thumb)
    thumb_data = etcpak.compress_bc1(tb.tobytes(), tb.shape[1], tb.shape[0])
    lin = (mips[0][:, :, :3] / 255.0) ** 2.2
    refl = [float(x) for x in lin.reshape(-1, 3).mean(axis=0)]
    data = []
    for m in mips:
        b = _to_bytes(m)
        data.append(enc(b.tobytes(), b.shape[1], b.shape[0]))
    write_container(path, mips[0].shape[1], mips[0].shape[0], fmt, flags, data,
                    (thumb.shape[1], thumb.shape[0], thumb_data), refl, bump_scale)


def write_container(path, w, h, fmt, flags, mips, thumb, reflectivity, bump_scale=1.0):
    """VTF 7.2 from data that is compressed already. mips: bytes per mip, largest first;
    thumb: (width, height, DXT1 data) of the small preview picture"""
    hdr = bytearray(80)
    struct.pack_into('<4sIII', hdr, 0, b'VTF\0', 7, 2, 80)
    struct.pack_into('<HHIHH', hdr, 16, w, h, flags, 1, 0)
    struct.pack_into('<3f', hdr, 32, *reflectivity)
    struct.pack_into('<fiBiBB', hdr, 48, bump_scale, fmt, len(mips), FMT_DXT1, thumb[0], thumb[1])
    struct.pack_into('<H', hdr, 63, 1)
    with open(path, 'wb') as f:
        f.write(hdr)
        f.write(thumb[2])
        for m in reversed(mips):  # smallest mip first
            f.write(m)


def thumbnail(buf):
    """(width, height, data) of the small DXT1 preview picture of a texture, or None"""
    hdr = read_header(buf)
    if hdr['low_format'] != FMT_DXT1 or not hdr['low_width']:
        return None
    size = _mip_bytes(FMT_DXT1, hdr['low_width'], hdr['low_height'])
    low = hdr['resources'].get(b'\x01\0\0')
    off = low[1] if low is not None else hdr['header_size']
    return hdr['low_width'], hdr['low_height'], bytes(buf[off:off + size])


# ----------------------------------------------------------------------------------------------
# DXT blocks, compressed here: slower than etcpak but as exact as the format allows
# ----------------------------------------------------------------------------------------------
def _blocks(img):
    """(h, w, C) -> (blocks, 16, C), blocks per row; the edge is repeated up to a multiple of 4"""
    h, w = img.shape[:2]
    ph, pw = (4 - h % 4) % 4, (4 - w % 4) % 4
    if ph or pw:
        img = np.pad(img, ((0, ph), (0, pw), (0, 0)), mode='edge')
    bh, bw = img.shape[0] // 4, img.shape[1] // 4
    return img.reshape(bh, 4, bw, 4, img.shape[2]).transpose(0, 2, 1, 3, 4).reshape(bh * bw, 16, img.shape[2]), bw


def _quantize565(c):
    """colours (n, 3) 0..255 -> their 5:6:5 numbers and what those are decoded to"""
    q = np.empty(c.shape, np.int64)
    q[:, 0] = np.clip(np.rint(c[:, 0] * (31.0 / 255.0)), 0, 31)
    q[:, 1] = np.clip(np.rint(c[:, 1] * (63.0 / 255.0)), 0, 63)
    q[:, 2] = np.clip(np.rint(c[:, 2] * (31.0 / 255.0)), 0, 31)
    back = np.stack([(q[:, 0] << 3) | (q[:, 0] >> 2), (q[:, 1] << 2) | (q[:, 1] >> 4), (q[:, 2] << 3) | (q[:, 2] >> 2)], axis=1)
    return q, back


def _nearest(px, e0, e1):
    """which of the four colours of a block every pixel gets, and the squared error of the block"""
    pal = np.stack([e0, e1, (2 * e0 + e1) // 3, (e0 + 2 * e1) // 3], axis=1).astype(np.float64)
    err = ((px[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(axis=3)
    idx = err.argmin(axis=2)
    return idx, np.take_along_axis(err, idx[:, :, None], axis=2)[:, :, 0].sum(axis=1)


_SHARE = np.array([1.0, 0.0, 2.0 / 3.0, 1.0 / 3.0])  # how much of the first colour an index stands for


def encode_color_blocks(px):
    """px (n, 16, 3) 0..255 -> (n, 8) uint8: the colour part of DXT1 / DXT5 blocks.
    The two colours of a block are put on the main axis of its pixels and then moved to where
    the error is smallest. The first one is always the larger number, as opaque DXT1 needs it."""
    px = np.asarray(px, np.float64)
    n = len(px)
    mean = px.mean(axis=1)
    d = px - mean[:, None, :]
    cov = np.einsum('nij,nik->njk', d, d)
    v = d[np.arange(n), (d * d).sum(axis=2).argmax(axis=1)]
    for _ in range(8):
        v = np.einsum('njk,nk->nj', cov, v)
        v = v / np.maximum(np.sqrt((v * v).sum(axis=1, keepdims=True)), 1e-9)
    t = np.einsum('nij,nj->ni', d, v)
    q0, e0 = _quantize565(mean + v * t.max(axis=1)[:, None])
    q1, e1 = _quantize565(mean + v * t.min(axis=1)[:, None])
    idx, err = _nearest(px, e0, e1)
    for _ in range(3):  # least squares for the two colours with the pixels assigned as they are
        a = _SHARE[idx]
        b = 1.0 - a
        aa, ab, bb = (a * a).sum(axis=1), (a * b).sum(axis=1), (b * b).sum(axis=1)
        det = aa * bb - ab * ab
        ok = det > 1e-6
        det = np.where(ok, det, 1.0)[:, None]
        ax, bx = (a[:, :, None] * px).sum(axis=1), (b[:, :, None] * px).sum(axis=1)
        n0, f0 = _quantize565((ax * bb[:, None] - bx * ab[:, None]) / det)
        n1, f1 = _quantize565((bx * aa[:, None] - ax * ab[:, None]) / det)
        idx2, err2 = _nearest(px, f0, f1)
        better = ok & (err2 < err)
        q0[better], q1[better], e0[better], e1[better] = n0[better], n1[better], f0[better], f1[better]
        idx[better], err[better] = idx2[better], err2[better]
    c0 = (q0[:, 0] << 11) | (q0[:, 1] << 5) | q0[:, 2]
    c1 = (q1[:, 0] << 11) | (q1[:, 1] << 5) | q1[:, 2]
    return _pack_color(c0, c1, idx)


def _pack_color(c0, c1, idx):
    """(n, 8) uint8 colour blocks; puts the larger colour first without changing what is shown"""
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    idx = np.where(swap[:, None], np.array([1, 0, 3, 2])[idx], idx)
    idx = np.where((c0 == c1)[:, None], 0, idx)  # equal colours would mean "black" for index 3 in DXT1
    bits = np.zeros(len(c0), np.int64)
    for i in range(16):
        bits |= idx[:, i].astype(np.int64) << (2 * i)
    out = np.empty((len(c0), 8), np.uint8)
    out[:, 0], out[:, 1], out[:, 2], out[:, 3] = c0 & 255, c0 >> 8, c1 & 255, c1 >> 8
    for i in range(4):
        out[:, 4 + i] = (bits >> (8 * i)) & 255
    return out


def encode_alpha_blocks(px):
    """px (n, 16) 0..255 -> (n, 8) uint8: the alpha part of DXT5 blocks"""
    v = np.clip(np.rint(np.asarray(px, np.float64)), 0, 255).astype(np.int64)
    a0, a1 = v.max(axis=1), v.min(axis=1)
    pal = np.empty((len(v), 8), np.int64)
    pal[:, 0], pal[:, 1] = a0, a1
    for i in range(1, 7):
        pal[:, i + 1] = ((7 - i) * a0 + i * a1) // 7
    idx = np.abs(v[:, :, None] - pal[:, None, :]).argmin(axis=2)
    idx[a0 == a1] = 0  # only one value in the block
    bits = np.zeros(len(v), np.int64)
    for i in range(16):
        bits |= idx[:, i].astype(np.int64) << (3 * i)
    out = np.empty((len(v), 8), np.uint8)
    out[:, 0], out[:, 1] = a0, a1
    for i in range(6):
        out[:, 2 + i] = (bits >> (8 * i)) & 255
    return out


def patch_dxt5(buf, old, new, alpha=False):
    """A copy of the DXT5 texture `buf` whose colours (or alpha) show `new` instead of `old`.

    old: the largest mip as it is decoded now (H, W, 4), new: what it should be (same shape,
    float). Every mip gets the difference between the two added, and only the blocks in which
    that difference can be seen are compressed again - the other bytes of the file, the other
    half of the changed blocks included, stay as they are.
    returns (bytes, number of blocks changed per mip)"""
    hdr, table = mip_table(buf)
    if hdr['format'] != FMT_DXT5:
        raise ValueError('not a DXT5 texture')
    out = bytearray(buf)
    part = slice(3, 4) if alpha else slice(0, 3)
    delta = np.asarray(new, np.float64)[:, :, part] - np.asarray(old, np.float64)[:, :, part]
    height, width = delta.shape[:2]
    counts = []
    for off, w, h in table:
        d = _halve(delta, width // w, height // h)
        changed = np.abs(d).max(axis=2, keepdims=True) >= 0.5
        which = np.nonzero(_blocks(changed)[0].any(axis=(1, 2)))[0]
        counts.append(len(which))
        if not len(which):
            continue
        now = decode_mip(out, FMT_DXT5, off, w, h).astype(np.float64)[:, :, part]
        px, bw = _blocks(np.clip(now + d, 0.0, 255.0))
        stored = np.frombuffer(out, np.uint8, len(px) * 16, off).reshape(-1, 16)
        if alpha:
            stored[which, 0:8] = encode_alpha_blocks(px[which][:, :, 0])
        else:
            stored[which, 8:16] = encode_color_blocks(px[which])
    return bytes(out), counts


def dxt5_to_dxt1(data):
    """the colours of DXT5 blocks as opaque DXT1 blocks that are decoded to exactly the same"""
    blocks = np.frombuffer(data, np.uint8).reshape(-1, 16)[:, 8:].astype(np.int64)
    c0 = blocks[:, 0] | (blocks[:, 1] << 8)
    c1 = blocks[:, 2] | (blocks[:, 3] << 8)
    bits = blocks[:, 4] | (blocks[:, 5] << 8) | (blocks[:, 6] << 16) | (blocks[:, 7] << 24)
    idx = np.stack([(bits >> (2 * i)) & 3 for i in range(16)], axis=1)
    return _pack_color(c0, c1, idx).tobytes()
