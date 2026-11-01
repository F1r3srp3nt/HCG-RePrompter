#!/usr/bin/env python3
"""Regenerates Branding/AppIcon.iconset and UI brand resources from Branding/hcg-logo.png.

Usage: python3 scripts/make-icons.py Branding/hcg-logo.png Branding/AppIcon.iconset Sources/RePrompterUI/Resources
Requires Pillow.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter
src, outdir, uires = sys.argv[1], sys.argv[2], sys.argv[3]
logo = Image.open(src).convert("RGB")
W = 1024
# Near-black navy field matching the logo background, with a subtle vignette lift in the centre.
bg = Image.new("RGB", (W, W), (4, 7, 14))
glow = Image.new("L", (W, W), 0)
ImageDraw.Draw(glow).ellipse((W*0.12, W*0.25, W*0.88, W*0.75), fill=60)
glow = glow.filter(ImageFilter.GaussianBlur(W*0.12))
bg = Image.composite(Image.new("RGB", (W, W), (10, 30, 60)), bg, glow)
# Crop the logo to its content (drop most of the empty dark margin).
lw, lh = logo.size
crop = logo.crop((int(lw*0.10), int(lh*0.06), int(lw*0.90), int(lh*0.94)))
target_w = int(W*0.84)
scale = target_w / crop.width
crop = crop.resize((target_w, int(crop.height*scale)), Image.LANCZOS)
# Blend with "lighten" so the logo's dark background merges into the field.
canvas = bg.copy()
x, y = (W - crop.width)//2, (W - crop.height)//2
region = canvas.crop((x, y, x+crop.width, y+crop.height))
from PIL import ImageChops
blended = ImageChops.lighter(region, crop)
feather = Image.new("L", crop.size, 0)
f = int(min(crop.size) * 0.12)
ImageDraw.Draw(feather).rectangle((f, f, crop.width - f, crop.height - f), fill=255)
feather = feather.filter(ImageFilter.GaussianBlur(f * 0.6))
canvas.paste(Image.composite(blended, region, feather), (x, y))
# macOS-style rounded square mask with transparent margin (824/1024 per Apple grid).
inset = 100; radius = 185
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle((inset, inset, W-inset, W-inset), radius=radius, fill=255)
icon_body = canvas.resize((W-2*inset, W-2*inset), Image.LANCZOS)
full = Image.new("RGBA", (W, W), (0, 0, 0, 0))
full.paste(icon_body, (inset, inset))
full.putalpha(mask)
full.save(f"{outdir}/../AppIcon-1024.png")
for base in [16, 32, 128, 256, 512]:
    for s in [1, 2]:
        px = base*s
        name = f"icon_{base}x{base}.png" if s == 1 else f"icon_{base}x{base}@2x.png"
        full.resize((px, px), Image.LANCZOS).save(f"{outdir}/{name}")
# UI resources: the wordmark (downscaled) and the square icon.
logo.resize((966, 407), Image.LANCZOS).save(f"{uires}/HCGLogo.png", optimize=True)
full.resize((512, 512), Image.LANCZOS).save(f"{uires}/AppIcon.png", optimize=True)
print("ok")
