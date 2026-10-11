"""Draws the placeholder EasyPlan icon (white calendar with a check on blue).

Writes icon.png (full, opaque, for iOS/web/legacy Android) and
icon_foreground.png (transparent, for Android adaptive icons). Replace both
with a designed icon at any time, then run `dart run flutter_launcher_icons`.
"""
from PIL import Image, ImageDraw

SIZE = 1024
BLUE = (59, 111, 224, 255)
WHITE = (255, 255, 255, 255)


def glyph(draw, scale, offset):
    """A calendar page with two binder rings and a check mark."""
    def box(x0, y0, x1, y1):
        return [offset + x0 * scale, offset + y0 * scale, offset + x1 * scale, offset + y1 * scale]

    draw.rounded_rectangle(box(0.20, 0.26, 0.80, 0.80), radius=0.08 * scale, fill=WHITE)
    draw.rectangle(box(0.20, 0.36, 0.80, 0.42), fill=BLUE)  # header band
    for x in (0.36, 0.64):
        draw.rounded_rectangle(box(x - 0.035, 0.18, x + 0.035, 0.33), radius=0.035 * scale, fill=WHITE)
    w = int(0.07 * scale)
    pts = [(0.37, 0.60), (0.47, 0.70), (0.65, 0.51)]
    draw.line([(offset + x * scale, offset + y * scale) for x, y in pts], fill=BLUE, width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        r = w / 2
        cx, cy = offset + x * scale, offset + y * scale
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLUE)


full = Image.new("RGBA", (SIZE, SIZE), BLUE)
glyph(ImageDraw.Draw(full), SIZE, 0)
full.convert("RGB").save("icon.png")  # iOS rejects transparency

# Adaptive icons crop to a circle/squircle: keep the glyph in the middle 70%.
fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
glyph(ImageDraw.Draw(fg), SIZE * 0.70, SIZE * 0.15)
fg.save("icon_foreground.png")
