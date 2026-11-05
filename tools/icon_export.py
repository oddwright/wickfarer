"""Build the placeholder app icon from the exported ship sprite.

Usage: python3 tools/icon_export.py art/

The App Store rejects icons with an alpha channel, so the icon is opaque: the
first Tallow Wren frame, scaled by a whole number, centred on the night colour
from project.godot.
"""
import os
import sys

from PIL import Image

ART = sys.argv[1]
SIZE = 1024
NIGHT = (8, 8, 26)  # boot_splash/bg_color in project.godot
FRAMES = 4

sheet = Image.open(os.path.join(ART, "ship_tallow_wren.png")).convert("RGBA")
frame = sheet.crop((0, 0, sheet.width // FRAMES, sheet.height))
frame = frame.crop(frame.getbbox())
scale = (SIZE - 2 * 64) // max(frame.width, frame.height)
ship = frame.resize((frame.width * scale, frame.height * scale), Image.NEAREST)
icon = Image.new("RGBA", (SIZE, SIZE), NIGHT + (255,))
icon.alpha_composite(ship, ((SIZE - ship.width) // 2, (SIZE - ship.height) // 2))
icon.convert("RGB").save(os.path.join(ART, "icon_1024.png"))
