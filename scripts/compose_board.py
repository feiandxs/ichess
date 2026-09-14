#!/usr/bin/env python3
"""Chroma-key chess sprites and composite a Duolingo-like board preview."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SESSION = Path(
    "/Users/feiandxs/.grok/sessions/"
    "%2FUsers%2Ffeiandxs%2Fworkspace%2Fichess/"
    "01a09946-e213-7b63-aeb3-6250585331e2/images"
)
ROOT = Path("/Users/feiandxs/workspace/ichess")
ASSETS = ROOT / "ichess/ichess/Assets.xcassets/Pieces"
PREVIEW_DIR = ROOT / "ichess/previews"
SCREENSHOT = Path(
    "/Users/feiandxs/.grok/sessions/"
    "%2FUsers%2Ffeiandxs%2Fworkspace%2Fichess/"
    "01a09946-e213-7b63-aeb3-6250585331e2/assets/"
    "image-de082ba8-f706-449d-b95a-053145333332.jpg"
)

# Generated files → logical names
WHITE = {
    "pawn": "3.jpg",
    "knight": "4.jpg",
    "rook": "5.jpg",
    "king": "6.jpg",
    "queen": "7.jpg",
    "bishop": "8.jpg",
}
BLACK = {
    "king": "9.jpg",
    "bishop": "10.jpg",
    "rook": "11.jpg",
    "knight": "12.jpg",
    "pawn": "13.jpg",
    "queen": "14.jpg",
}

# Relative on-board heights (king = 1)
HEIGHT_RATIO = {
    "pawn": 0.68,
    "rook": 0.80,
    "knight": 0.86,
    "bishop": 0.88,
    "queen": 0.95,
    "king": 1.00,
}

# Dark-mode board, sampled from the Duolingo screenshot
BG = (20, 31, 37, 255)
LIGHT = (35, 52, 59, 255)
DARK = (22, 35, 43, 255)


def chroma_key(src: Path) -> Image.Image:
    """Flood-fill from the edges using the corner magenta, then despill the fringe."""
    from collections import deque

    im = Image.open(src).convert("RGBA")
    w, h = im.size
    pix = im.load()
    refs = [
        pix[4, 4][:3],
        pix[w - 5, 4][:3],
        pix[4, h - 5][:3],
        pix[w - 5, h - 5][:3],
    ]
    ref = tuple(sum(c[i] for c in refs) // 4 for i in range(3))

    def dist(c: tuple[int, int, int]) -> int:
        return abs(c[0] - ref[0]) + abs(c[1] - ref[1]) + abs(c[2] - ref[2])

    hard, soft = 90, 130
    visited = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))

    while q:
        x, y = q.popleft()
        i = y * w + x
        if visited[i]:
            continue
        visited[i] = 1
        r, g, b, a = pix[x, y]
        d = dist((r, g, b))
        if d > soft:
            continue
        if d <= hard:
            pix[x, y] = (r, g, b, 0)
        else:
            t = (d - hard) / (soft - hard)
            gray = int(g * 0.6 + r * 0.2 + b * 0.2)
            pix[x, y] = (
                int(r * t + gray * (1 - t)),
                g,
                int(b * t + gray * (1 - t)),
                int(a * t),
            )
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny * w + nx]:
                q.append((nx, ny))

    # Restore interior holes, then despill only the fringe.
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            neighbors = [
                pix[x + dx, y + dy][3]
                for dx, dy in (
                    (-1, 0),
                    (1, 0),
                    (0, -1),
                    (0, 1),
                    (-1, -1),
                    (1, -1),
                    (-1, 1),
                    (1, 1),
                )
            ]
            if a < 250 and min(neighbors) > 200:
                pix[x, y] = (r, g, b, 255)
                r, g, b, a = pix[x, y]
            if min(neighbors) == 0:
                over = min(r, b) - g
                if over > 6:
                    pix[x, y] = (
                        max(0, r - int(over * 0.9)),
                        g,
                        max(0, b - int(over * 0.75)),
                        a,
                    )
    return im


def opaque_bbox(im: Image.Image, threshold: int = 24) -> tuple[int, int, int, int]:
    alpha = im.split()[-1]
    # tighten crop
    mask = alpha.point(lambda p: 255 if p >= threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        return (0, 0, im.width, im.height)
    pad = max(4, min(im.width, im.height) // 80)
    l, t, r, b = bbox
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    return (l, t, r, b)


def imageset_json(filename: str) -> dict:
    return {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }


def write_imageset(name: str, im: Image.Image) -> Path:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    png_name = f"{name}.png"
    dest = folder / png_name
    cropped = im.crop(opaque_bbox(im))
    # Cap long edge so the catalog stays light; SwiftUI scales from here
    max_edge = 512
    scale = min(1.0, max_edge / max(cropped.width, cropped.height))
    if scale < 1.0:
        cropped = cropped.resize(
            (max(1, int(cropped.width * scale)), max(1, int(cropped.height * scale))),
            Image.Resampling.LANCZOS,
        )
    cropped.save(dest, "PNG")
    (folder / "Contents.json").write_text(
        json.dumps(imageset_json(png_name), indent=2) + "\n"
    )
    return dest


def place_piece(
    board: Image.Image,
    sprite: Image.Image,
    col: int,
    row: int,
    square: int,
    origin: tuple[int, int],
    kind: str,
    flip: bool = False,
) -> None:
    piece = sprite
    if flip:
        piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
    bbox = opaque_bbox(piece)
    cropped = piece.crop(bbox)
    target_h = int(square * 0.88 * HEIGHT_RATIO[kind])
    scale = target_h / cropped.height
    target_w = max(1, int(cropped.width * scale))
    # Don't let width overflow the square
    max_w = int(square * 0.90)
    if target_w > max_w:
        scale = max_w / cropped.width
        target_w = max_w
        target_h = max(1, int(cropped.height * scale))
    resized = cropped.resize((target_w, target_h), Image.Resampling.LANCZOS)

    ox, oy = origin
    cx = ox + col * square + square // 2
    # Sit slightly low in the square, like a piece standing on it
    base_y = oy + row * square + int(square * 0.92)
    x = cx - resized.width // 2
    y = base_y - resized.height

    # Soft contact shadow
    shadow = Image.new("RGBA", (resized.width, max(8, resized.height // 10)), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse((0, 0, shadow.width - 1, shadow.height - 1), fill=(0, 0, 0, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=3))
    sx = cx - shadow.width // 2
    sy = base_y - shadow.height // 2
    board.alpha_composite(shadow, (sx, sy))
    board.alpha_composite(resized, (x, y))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def compose_board(sprites: dict[str, Image.Image]) -> Image.Image:
    square = 140
    margin = 36
    board_px = square * 8
    canvas_w = board_px + margin * 2
    canvas_h = board_px + margin * 2 + 24
    canvas = Image.new("RGBA", (canvas_w, canvas_h), BG)

    board = Image.new("RGBA", (board_px, board_px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(board)
    for row in range(8):
        for col in range(8):
            # a1 is dark from white's view? Standard: a1 is dark.
            # File 0 = a, rank row 7 = rank 1. Light if (col+row) even from top-left
            # Top-left (a8) is light in standard diagrams.
            color = LIGHT if (col + row) % 2 == 0 else DARK
            x0, y0 = col * square, row * square
            draw.rectangle((x0, y0, x0 + square, y0 + square), fill=color)

    origin = (0, 0)
    back = ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]

    # Black back rank (row 0) and pawns (row 1)
    for col, kind in enumerate(back):
        flip = kind == "knight" and col == 6  # g-file faces center
        place_piece(board, sprites[f"black_{kind}"], col, 0, square, origin, kind, flip)
    for col in range(8):
        place_piece(board, sprites["black_pawn"], col, 1, square, origin, "pawn")

    # White pawns (row 6) and back rank (row 7)
    for col in range(8):
        place_piece(board, sprites["white_pawn"], col, 6, square, origin, "pawn")
    for col, kind in enumerate(back):
        flip = kind == "knight" and col == 6
        place_piece(board, sprites[f"white_{kind}"], col, 7, square, origin, kind, flip)

    mask = rounded_mask((board_px, board_px), radius=28)
    board.putalpha(ImageChops_and(board.split()[-1], mask))
    canvas.alpha_composite(board, (margin, margin))
    return canvas


def ImageChops_and(a: Image.Image, b: Image.Image) -> Image.Image:
    from PIL import ImageChops

    return ImageChops.multiply(a, b)


def sample_screenshot() -> None:
    if not SCREENSHOT.exists():
        print("no screenshot")
        return
    im = Image.open(SCREENSHOT).convert("RGB")
    w, h = im.size
    print(f"screenshot {w}x{h}")
    # Probe a few squares: board sits in the lower-middle of the phone shot
    probes = [
        ("bg", (w // 2, int(h * 0.06))),
        ("light-ish", (int(w * 0.22), int(h * 0.48))),
        ("dark-ish", (int(w * 0.32), int(h * 0.48))),
        ("light2", (int(w * 0.55), int(h * 0.52))),
        ("dark2", (int(w * 0.45), int(h * 0.52))),
    ]
    for name, (x, y) in probes:
        print(name, x, y, im.getpixel((x, y)))


def main() -> None:
    sample_screenshot()
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    sprites: dict[str, Image.Image] = {}
    for color, mapping in (("white", WHITE), ("black", BLACK)):
        for kind, filename in mapping.items():
            src = SESSION / filename
            keyed = chroma_key(src)
            name = f"{color}_{kind}"
            sprites[name] = keyed
            write_imageset(name, keyed)
            keyed.save(PREVIEW_DIR / f"{name}.png")
            print("keyed", name, keyed.size)

    preview = compose_board(sprites)
    out = PREVIEW_DIR / "board_preview.png"
    preview.save(out)
    print("preview", out, preview.size)


if __name__ == "__main__":
    main()
