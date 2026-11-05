# V16 Studio Mascots

12 original mascot models and 12 transparent 256×256 PNG shop icons, split into three batches of four. Models use only native Parts, 15–30 Parts each, no scripts/meshes/textures or PointLights. Body is the PrimaryPart. Pivot is centered at base Y=0, forward +Z, height 2–3 studs. Ordinary mascots have no Neon.

Each batch includes model geometry renders, model/icon comparison sheet, icon sheet, exact generation prompts/source paths and validation. The shared source builder recreates all native models and renders. Requires Python, Pillow and NumPy (`pip install pillow numpy`); run `python source/build_mascots.py`.

Icons use built-in ImageGen and depict the same mascot theme and color palette in polished V3 menu style. Models are deliberately simple native primitives for mobile use. Studio import/play-test and game integration remain for the developers; this package contains no game logic or uploaded asset IDs.
