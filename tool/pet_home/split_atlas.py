"""Cut the approved generated 4x4 atlas; keep true alpha and remove stray dust.
Usage: python tool/pet_home/split_atlas.py ATLAS.png ROOM.png
Source originals remain in /workspace/generated_images (never overwrite them).
"""
import sys
from pathlib import Path
from PIL import Image
import numpy as np
from scipy.ndimage import label

names = ['sofa', 'armchair', 'daybed', 'cottage', 'rug_cream', 'rug_sage',
         'monstera', 'daisies', 'lamp', 'frame', 'bowl', 'sponge', 'ball',
         'petting', 'strawberry', 'towel']
out = Path('assets/pet_home')
atlas = Image.open(sys.argv[1]).convert('RGBA')
a = np.array(atlas)
components, count = label(a[:, :, 3] > 35)
sizes = np.bincount(components.ravel())
# Generated objects may cross ideal cell edges. Assign WHOLE connected
# components by their centroid, then crop, so sofa legs are never severed.
groups = [[] for _ in names]
from scipy.ndimage import center_of_mass
for component in np.flatnonzero(sizes >= 1000):
    if component == 0:
        continue
    cy, cx = center_of_mass(a[:, :, 3], components, int(component))
    index = min(3, int(cy*4/atlas.height))*4 + min(3, int(cx*4/atlas.width))
    groups[index].append(component)
for i, name in enumerate(names):
    pixels = a.copy()
    pixels[:, :, 3] = np.where(np.isin(components, groups[i]), a[:, :, 3], 0)
    cell = Image.fromarray(pixels)
    bbox = cell.getbbox()
    if bbox:
        cell = cell.crop(bbox)
    canvas = Image.new('RGBA', (320, 320))
    cell.thumbnail((296, 296), Image.Resampling.LANCZOS)
    canvas.alpha_composite(cell, ((320-cell.width)//2, (320-cell.height)//2))
    canvas.save(out / f'{name}.webp', lossless=True)
Image.open(sys.argv[2]).convert('RGB').resize((1024, 1024), Image.Resampling.LANCZOS).save(out / 'room.webp', quality=91)
# Human inspection sheet; not bundled into the app.
preview = Image.new('RGB', (1280, 1280), '#f7eddb')
for i, name in enumerate(names):
    cell = Image.open(out / f'{name}.webp')
    preview.paste(cell, ((i%4)*320, (i//4)*320), cell)
preview.save('/tmp/pet-home-sprites.png')
