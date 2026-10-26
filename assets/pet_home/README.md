# Pet home art

Original generated artwork for Tethered, approved by the owner on 26 October
2026. Created with OpenAI image generation from the approved chat concept;
no Togetherly catalog images are copied into these new assets.

`room.webp`: empty room, 1024 square. Furniture and care objects: separate
320-square lossless WebP sprites with transparent padding and consistent
scale within each cell. The app positions each sprite independently.

Palette: cream #F7EDDB, ink #563F2E, sage #939A77, terracotta #CD8265,
honey #C79558. Original generated atlas is split with
`tool/pet_home/split_atlas.py` (Pillow, NumPy, SciPy). Originals are committed
in `tool/pet_home/source/`, outside the app bundle. Regenerate from the repo
root with `python tool/pet_home/split_atlas.py tool/pet_home/source/atlas.png
tool/pet_home/source/room.png`. The reference sheet is not a screenshot/background in the UI.
