# Nook Monoline (单线轮廓)

Original chess artwork drawn for Nook Chess (catalog id `nook_mono`). Authored from scratch as SVG primitives and paths by the generator scripts in `artwork/piece-lab/`; no third-party chess piece image or SVG path was used or traced.

Twelve transparent SVGs share a 100 x 100 coordinate system. App PNGs are rasterized at 256 x 256 with @resvg/resvg-js via `scripts/pack_piece_sets.mjs --originals-only`, which shifts the viewBox so the union bounding box of the twelve pieces is centered in the square. These SVGs are the editable masters.
