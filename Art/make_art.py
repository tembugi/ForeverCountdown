# Draws the infinity sign beside "Forever launches" and saves it as ../Infinity.tga, the texture
# the addon shows. Run: python3 Art/make_art.py in the addon folder.
#
# The drawing is the one the user chose (option A, 2026-10-05): Bernoulli's lemniscate stretched
# up 1.25, a calligraphic stroke (thick across a pen nib held at -38 degrees, thin along it),
# silver shading top to bottom, a thin dark edge, and the strand through one crossing drawn again
# on top. Drawn in the game from ~200 small discs it wobbled; as one image it is smooth.
#
# The texture covers 28 x 14 UI units with the 24-unit-wide sign centered in it; the addon sizes
# it from INFINITY_WIDTH with the same ratios (ART_WIDTH, ART_HEIGHT in ForeverCountdown.lua) and
# runs its light along the same curve.
import math
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SIGN_WIDTH = 24.0                     # UI units, INFINITY_WIDTH in the addon
SIGN_HEIGHT = SIGN_WIDTH * 60 / 124
ART_WIDTH, ART_HEIGHT = 28.0, 14.0    # UI units the texture covers
SIZE = (128, 64)                      # the game reads TGA: 32-bit, uncompressed, power-of-two
SUPERSAMPLE = 8
THIN, THICK, EDGE = 1.1, 2.2, 0.9     # stroke widths and the dark edge, UI units
NIB = math.radians(-38)
STEPS = 720
EDGE_COLOR = (0.23, 0.16, 0.08)

def silver(f):
    if f < 0.55:
        k = f / 0.55
        return (1 - 0.18 * k, 1 - 0.21 * k, 1 - 0.29 * k)
    k = (f - 0.55) / 0.45
    return (0.82 + 0.12 * k, 0.79 + 0.12 * k, 0.71 + 0.14 * k)

scale = SIGN_WIDTH / 124
points = []
for i in range(STEPS):
    t = 2 * math.pi * i / STEPS
    d = 1 + math.sin(t) ** 2
    points.append(((62 + 50 * math.cos(t) / d) * scale, (30 + 62.5 * math.sin(t) * math.cos(t) / d) * scale))

def width(i):
    p, q = points[(i - 1) % STEPS], points[(i + 1) % STEPS]
    angle = math.atan2(q[1] - p[1], q[0] - p[0])
    return THIN + (THICK - THIN) * abs(math.sin(angle - NIB))

W, H = SIZE[0] * SUPERSAMPLE, SIZE[1] * SUPERSAMPLE
per_unit = W / ART_WIDTH
offset_x = (ART_WIDTH - SIGN_WIDTH) / 2
offset_y = (ART_HEIGHT - SIGN_HEIGHT) / 2
# Transparent pixels carry the edge color, so the game's filtering can't bleed in another color.
color = Image.new("RGB", (W, H), tuple(int(c * 255) for c in EDGE_COLOR))
alpha = Image.new("L", (W, H), 0)
draw_color, draw_alpha = ImageDraw.Draw(color), ImageDraw.Draw(alpha)

def disc(x, y, size, rgb):
    r = size / 2 * per_unit
    cx, cy = (x + offset_x) * per_unit, (y + offset_y) * per_unit
    draw_color.ellipse((cx - r, cy - r, cx + r, cy + r), fill=tuple(int(c * 255) for c in rgb))
    draw_alpha.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)

def stroke(first, last, extra, shade):
    for i in range(first, last):
        x, y = points[i % STEPS]
        disc(x, y, width(i) + extra, shade(y / SIGN_HEIGHT))

stroke(0, STEPS, EDGE, lambda f: EDGE_COLOR)
stroke(0, STEPS, 0, silver)
over_first, over_last = int(STEPS * 0.19), math.ceil(STEPS * 0.31)
trim = int(STEPS * 0.04)
stroke(over_first + trim, over_last - trim, EDGE, lambda f: EDGE_COLOR)
stroke(over_first, over_last, 0, silver)

image = color.convert("RGBA")
image.putalpha(alpha)
image = image.resize(SIZE, Image.LANCZOS)
image.save(os.path.join(HERE, "..", "Infinity.tga"))
print("saved Infinity.tga", SIZE)
