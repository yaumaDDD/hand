"""Puts a title in the style of the Z-City logo on a picture (docs/*.png).

    python tools/title_picture.py SOURCE.png OUT.png --font Bahnschrift.ttf \
        --lines "Z-CITY" "BACK HOLSTER" --behind 68,60,160,420 298,50,140,400
    python tools/title_picture.py SOURCE.png OUT.png --font Bahnschrift.ttf --bouncy \
        --lines "REMORSEIM" "GUNS FOR Z-CITY" ...

The first letter of the first line is red, the rest white; the letters are bold, slanted and
squashed from top to bottom. --behind RECTS: the figures inside these rectangles (x,y,w,h) are
cut out (GrabCut, needs opencv-python-headless) and stay in front of the title.
--blood SEED: blood smeared over the letters (and a little past them); another seed, other smears.
Needs pillow and numpy.
"""
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 4  # supersampling
RED, WHITE = (222, 32, 28, 255), (245, 245, 245, 255)
PURE, BLACK = (12, 12, 12, 255), (255, 255, 255, 255)  # the jumping word: black letters, white edge


def line(font, parts, tracking, squash=0.72, slant=0.22):
    width = sum(font.getlength(ch) + tracking for text, _ in parts for ch in text)
    asc, desc = font.getmetrics()
    im = Image.new('RGBA', (int(width) + 40 * S, asc + desc), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x = 10 * S
    for text, colour in parts:
        for ch in text:
            d.text((x, 0), ch, font=font, fill=colour, stroke_width=S, stroke_fill=colour)
            x += font.getlength(ch) + tracking
    im = im.crop(im.getbbox())
    im = im.resize((im.width, int(im.height * squash)), Image.LANCZOS)
    wide = Image.new('RGBA', (im.width + int(im.height * slant) + 2, im.height), (0, 0, 0, 0))
    wide.paste(im, (0, 0))
    return wide.transform(wide.size, Image.AFFINE, (1, slant, -slant * im.height, 0, 1, 0), Image.BICUBIC)


def bouncy(font, text, squash=0.82, slant=0.2):
    """A word whose letters jump: each one has its own size, tilt and height, one of them is small
    (the logo of Remorse). All white."""
    sizes = (1.22, 1.0, 0.92, 0.7, 1.08, 1.0, 1.04, 0.86, 0.98)
    tilts = (7, -4, 6, -9, 5, 8, -6, 5, -7)
    lifts = (0.0, 0.05, -0.06, -0.1, 0.03, -0.05, 0.06, -0.04, 0.02)
    asc, desc = font.getmetrics()
    letters, x = [], 0
    for i, ch in enumerate(text):
        k = i % len(sizes)
        if sizes[k] < 0.8:
            ch = ch.lower()
        im = Image.new('RGBA', (int(font.getlength(ch)) + 40 * S, asc + desc), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((20 * S, 0), ch, font=font, fill=PURE, stroke_width=int(1.6 * S), stroke_fill=PURE)
        im = im.crop(im.getbbox())
        im = im.resize((int(im.width * sizes[k]), int(im.height * sizes[k] * squash)), Image.LANCZOS)
        wide = Image.new('RGBA', (im.width + int(im.height * slant) + 2, im.height), (0, 0, 0, 0))
        wide.paste(im, (0, 0))
        im = wide.transform(wide.size, Image.AFFINE, (1, slant, -slant * im.height, 0, 1, 0), Image.BICUBIC)
        im = im.rotate(tilts[k], Image.BICUBIC, expand=True)
        letters.append((im, x, lifts[k]))
        x += int(im.width * 0.88)
    height = max(im.height for im, _, _ in letters)
    out = Image.new('RGBA', (x + 40 * S, int(height * 1.5)), (0, 0, 0, 0))
    for im, left, lift in letters:
        out.alpha_composite(im, (left, int(height * 1.25 - im.height + lift * height)))
    return out.crop(out.getbbox())


def blood(size, alpha, seed):
    """The smears: (layer over the letters, layer beside them). Wipes of a hand - streaks along
    the wipe, torn by noise - and a few drops."""
    rng = np.random.default_rng(seed)
    w, h = size
    box = alpha.getbbox()
    x0, y0, x1, y1 = box
    wipes = Image.new('L', size, 0)
    d = ImageDraw.Draw(wipes)
    for _ in range(4):  # where the hand went
        cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
        lx, ly = rng.uniform(0.25, 0.5) * (x1 - x0), rng.uniform(0.16, 0.3) * (y1 - y0)
        d.ellipse((cx - lx, cy - ly, cx + lx, cy + ly), fill=255)
    wipes = wipes.filter(ImageFilter.GaussianBlur(5))
    streaks = Image.fromarray((rng.random((h, max(2, w // 22))) * 255).astype(np.uint8)).resize(size, Image.BICUBIC)
    grain = Image.fromarray((rng.random((h // 2, w // 2)) * 255).astype(np.uint8)).resize(size, Image.BICUBIC)
    m = np.asarray(wipes, float) / 255 * (0.25 + 0.75 * np.asarray(streaks, float) / 255)
    m = np.clip((m - 0.3 + 0.12 * (np.asarray(grain, float) / 255 - 0.5)) * 4.0, 0, 1)
    m = Image.fromarray((m * 255).astype(np.uint8))
    d = ImageDraw.Draw(m)
    for _ in range(14):  # drops
        cx, cy, r = rng.uniform(x0 - 6, x1 + 6), rng.uniform(y0 - 8, y1 + 10), rng.uniform(0.6, 2.2)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=int(rng.uniform(150, 255)))
    m = m.rotate(-5, Image.BICUBIC, center=((x0 + x1) / 2, (y0 + y1) / 2)).filter(ImageFilter.GaussianBlur(0.6))
    m = np.asarray(m, float) / 255
    a = np.asarray(alpha, float) / 255
    dark = 0.75 + 0.25 * np.asarray(grain, float)[..., None] / 255
    rgb = (np.array([150, 8, 10]) * dark).astype(np.uint8)
    on = np.dstack([rgb, (m * a * 240).astype(np.uint8)])
    off = np.dstack([(rgb * 0.8).astype(np.uint8), (m * (1 - a) * 150).astype(np.uint8)])
    return Image.fromarray(on, 'RGBA'), Image.fromarray(off, 'RGBA')


def figures(path, rects, add=(), drop_green=True):
    import cv2
    img = cv2.imread(path)
    full = np.zeros(img.shape[:2], np.uint8)
    for rect in rects:
        m = np.zeros(img.shape[:2], np.uint8)
        bg, fg = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
        cv2.grabCut(img, m, tuple(rect), bg, fg, 8, cv2.GC_INIT_WITH_RECT)
        full |= np.where((m == 1) | (m == 3), 255, 0).astype(np.uint8)
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    if drop_green:  # grass that got into a cut-out
        full[(hsv[..., 0] > 30) & (hsv[..., 0] < 75) & (hsv[..., 1] > 70)] = 0
    for x, y, w, h, low in add:  # a bright thing in front of a dark background (x,y,w,h,brightness)
        part = hsv[y:y + h, x:x + w, 2] >= low
        full[y:y + h, x:x + w][part] = 255
    full = cv2.morphologyEx(full, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    return Image.fromarray(full).filter(ImageFilter.GaussianBlur(0.8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('source'); ap.add_argument('out')
    ap.add_argument('--font', required=True)
    ap.add_argument('--lines', nargs='+', required=True)
    ap.add_argument('--width', type=int, default=300, help='width of the widest (last) line')
    ap.add_argument('--first', type=float, default=0.62, help='width of the first line, share of --width')
    ap.add_argument('--anchor', default='right', choices=['right', 'centre'])
    ap.add_argument('--x', type=int, required=True, help='right edge or centre of the title')
    ap.add_argument('--y', type=int, required=True, help='vertical centre of the title')
    ap.add_argument('--gap', type=int, default=9)
    ap.add_argument('--behind', nargs='*', default=[])
    ap.add_argument('--add', nargs='*', default=[])
    ap.add_argument('--blood', type=int, default=None, help='smear blood over the title (seed)')
    ap.add_argument('--bouncy', action='store_true', help='the first line with jumping letters, white; '
                    'in the other lines the first Z is red')
    ap.add_argument('--squash', type=float, default=0.72, help='how flat the usual lines are')
    a = ap.parse_args()

    src = Image.open(a.source).convert('RGBA')
    font = ImageFont.truetype(a.font, 46 * S)
    font.set_variation_by_name('Bold')
    rows = []
    for i, text in enumerate(a.lines):
        parts = [(text[0], RED), (text[1:], WHITE)] if i == 0 else [(text, WHITE)]
        if a.bouncy and 'Z' in text and i:
            z = text.index('Z')
            parts = [(text[:z], WHITE), ('Z', RED), (text[z + 1:], WHITE)]
        if a.bouncy and i == 0:
            im = bouncy(font, text)
        else:
            im = line(font, parts, (5 if i == 0 else 3) * S, squash=a.squash)
        width = a.width if i == len(a.lines) - 1 else int(a.width * a.first)
        im = im.resize((width * S, int(im.height * width * S / im.width)), Image.LANCZOS)
        if a.bouncy and i == 0:  # a thick black edge, as the word stands on black in the logo
            pad = 5 * S
            wide = Image.new('RGBA', (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
            wide.alpha_composite(im, (pad, pad))
            back = Image.new('RGBA', wide.size, (0, 0, 0, 0))
            back.paste(BLACK, (0, 0), wide.getchannel('A').filter(ImageFilter.MaxFilter(4 * S + 1)).filter(ImageFilter.GaussianBlur(S / 2)))
            im = Image.alpha_composite(back, wide)
        rows.append(im)
    total = sum(r.height for r in rows) + a.gap * S * (len(rows) - 1)
    layer = Image.new('RGBA', (src.width * S, src.height * S), (0, 0, 0, 0))
    top = a.y * S - total // 2
    for r in rows:
        left = a.x * S - r.width if a.anchor == 'right' else a.x * S - r.width // 2
        layer.alpha_composite(r, (left, top))
        top += r.height + a.gap * S
    layer = layer.resize(src.size, Image.LANCZOS)
    alpha = layer.getchannel('A')
    shadow = Image.new('RGBA', src.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 255), (2, 3), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(2.5))
    edge = Image.new('RGBA', src.size, (0, 0, 0, 0))
    edge.paste((10, 10, 10, 230), (0, 0), alpha.filter(ImageFilter.MaxFilter(3)))
    out = Image.alpha_composite(Image.alpha_composite(Image.alpha_composite(src, shadow), edge), layer)
    if a.blood is not None:
        on, off = blood(src.size, alpha, a.blood)
        out = Image.alpha_composite(Image.alpha_composite(out, off), on)
    if a.behind:
        rects = [[int(v) for v in r.split(',')] for r in a.behind]
        add = [[int(v) for v in r.split(',')] for r in a.add]
        out = Image.composite(src, out, figures(a.source, rects, add))
    out.convert('RGB').save(a.out)


if __name__ == '__main__':
    main()
