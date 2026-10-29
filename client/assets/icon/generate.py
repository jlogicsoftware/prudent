"""Render Prudent's launcher artwork; requires Pillow. Run from the repository root."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path('client')
SIZE = 1024

def artwork(foreground=False):
    image = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0) if foreground else '#004b48')
    draw = ImageDraw.Draw(image)
    # A continuous outline: a square lower-left corner anchors the rounded monogram.
    points = [(310, 400), (310, 370)]

    def curve(control1, control2, end):
        start = points[-1]
        for step in range(1, 33):
            t = step / 32
            u = 1 - t
            points.append(tuple(
                u**3 * start[i] + 3 * u**2 * t * control1[i]
                + 3 * u * t**2 * control2[i] + t**3 * end[i]
                for i in (0, 1)
            ))

    curve((310, 315), (350, 275), (405, 275))
    points.append((555, 275))
    curve((650, 275), (725, 350), (725, 450))
    curve((725, 550), (650, 625), (555, 625))
    points.extend([(450, 625), (450, 725)])
    curve((450, 752), (436, 765), (410, 765))
    points.extend([(310, 765), (310, 465), (550, 465)])
    curve((570, 465), (582, 452), (582, 435))
    curve((582, 418), (570, 400), (550, 400))
    points.append((310, 400))
    draw.polygon(points, fill='#f5f2e7')
    return image

def save(path, size, foreground=False, safe=False):
    image = artwork(foreground)
    if not foreground and not safe:
        image = image.crop((128, 128, 896, 896))
    image = image.resize((size, size), Image.Resampling.LANCZOS)
    if not foreground:
        image = image.convert('RGB')
    image.save(path)

for platform in ('ios', 'macos'):
    folder = ROOT / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
    for item in json.loads((folder / 'Contents.json').read_text())['images']:
        if 'filename' in item:
            size = round(float(item['size'].split('x')[0]) * int(item['scale'][0]))
            save(folder / item['filename'], size)
for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
    save(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
    save(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png', size * 108 // 48, True)
save(ROOT / 'web/favicon.png', 32)
for size in (192, 512):
    for suffix in ('', '-maskable'):
        save(ROOT / f'web/icons/Icon{suffix}-{size}.png', size, safe=bool(suffix))
