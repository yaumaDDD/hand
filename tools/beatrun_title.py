"""Puts a title on top of a picture: the Beatrun word taken from its logo screenshot (the pixel
letters themselves, kept blocky) and the other lines in the usual Z-City style of title_picture.py.

    python tools/beatrun_title.py SOURCE.png LOGO.png OUT.png --font DejaVuSans-Bold.ttf \
        --lines "For Z-City" --word-width 340 --line-width 230 --x 22 --y 16

The logo screenshot is thresholded: the white letters of its top band are reduced to their block
grid and blown up again with square blocks, so the word stays pixel art at any size. The other
lines are drawn as in title_picture.py (bold, slanted, squashed, a red Z in Z-City), and the whole
title gets the same dark edge and shadow. Needs pillow and numpy.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from title_picture import S, RED, WHITE, line


def logo_word(path, width, thresh=220):
    """The white pixel word of the top line of the logo screenshot, blown up with NEAREST so the
    pixels stay exactly as the logo drew them."""
    grey = np.asarray(Image.open(path).convert('L'))
    mask = np.where(grey > thresh, 255, 0).astype(np.uint8)
    rows = mask.sum(axis=1) > 0
    top = int(np.argmax(rows))  # the first line of the logo: from its first row to its first gap
    rest = rows[top:]
    bottom = top + int(np.argmin(rest)) if not rest.all() else len(rows)
    band = mask[top:bottom]
    ys, xs = np.nonzero(band)
    band = band[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    word = Image.fromarray(band, 'L')
    height = max(1, round(word.height * width / word.width))
    word = word.resize((width, height), Image.NEAREST)
    out = Image.new('RGBA', word.size, (0, 0, 0, 0))
    out.paste(WHITE, (0, 0), word)
    return out


def our_line(font, text, squash, width):
    """A line in the usual style; the Z of Z-City is red, as in the bouncy titles."""
    if 'Z' in text:
        z = text.index('Z')
        parts = [(text[:z], WHITE), ('Z', RED), (text[z + 1:], WHITE)]
    else:
        parts = [(text, WHITE)]
    im = line(font, parts, 3 * S, squash=squash)
    return im.resize((width, max(1, int(im.height * width / im.width))), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('source'); ap.add_argument('logo'); ap.add_argument('out')
    ap.add_argument('--font', required=True)
    ap.add_argument('--lines', nargs='+', required=True, help='the lines under the pixel word')
    ap.add_argument('--word-width', type=int, default=340)
    ap.add_argument('--line-width', type=int, default=230)
    ap.add_argument('--x', type=int, default=22, help='left edge of the title')
    ap.add_argument('--y', type=int, default=16, help='top edge of the title')
    ap.add_argument('--gap', type=int, default=10)
    ap.add_argument('--squash', type=float, default=0.72)
    a = ap.parse_args()

    src = Image.open(a.source).convert('RGBA')
    word = logo_word(a.logo, a.word_width)
    font = ImageFont.truetype(a.font, 46 * S)
    try:
        font.set_variation_by_name('Bold')
    except Exception:
        pass
    rows = [word] + [our_line(font, text, a.squash, a.line_width) for text in a.lines]

    layer = Image.new('RGBA', src.size, (0, 0, 0, 0))
    top = a.y
    for r in rows:
        layer.alpha_composite(r, (a.x, top))
        top += r.height + a.gap
    alpha = layer.getchannel('A')
    shadow = Image.new('RGBA', src.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 255), (2, 3), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(2.5))
    edge = Image.new('RGBA', src.size, (0, 0, 0, 0))
    edge.paste((10, 10, 10, 230), (0, 0), alpha.filter(ImageFilter.MaxFilter(3)))
    out = Image.alpha_composite(Image.alpha_composite(Image.alpha_composite(src, shadow), edge), layer)
    out.convert('RGB').save(a.out)
    print('saved', a.out, out.size, 'word', word.size)


if __name__ == '__main__':
    main()
