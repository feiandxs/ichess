#!/usr/bin/env node
import { Resvg } from "@resvg/resvg-js";
import { mkdirSync, readdirSync, readFileSync, writeFileSync, copyFileSync, existsSync, statSync } from "fs";
import { join } from "path";

const SRC = "/tmp/chess-compare";
const CLAY = "/Users/feiandxs/workspace/ichess/ichess/ichess/Assets.xcassets/Pieces";
const OUT = "/Users/feiandxs/workspace/ichess/ichess/ichess/PieceSets";
const SIZE = 256;

const LI_MAP = {
  wP: "white_pawn", wN: "white_knight", wB: "white_bishop",
  wR: "white_rook", wQ: "white_queen", wK: "white_king",
  bP: "black_pawn", bN: "black_knight", bB: "black_bishop",
  bR: "black_rook", bQ: "black_queen", bK: "black_king",
};

const NAMES = {
  nook_flat: ["Nook Flat", "自绘 SVG", "icon", "centered"],
  nook_soft: ["Soft Geometry", "自绘 SVG", "icon", "square"],
  nook_crisp: ["Crisp Facets", "自绘 SVG", "icon", "square"],
  nook_block: ["Bold Blocks", "自绘 SVG", "icon", "square"],
  nook_mono: ["Monoline", "自绘 SVG", "icon", "square"],
  nook_badge: ["Badge Discs", "自绘 SVG", "icon", "square"],
  spatial: ["Spatial", "Lichess", "icon"],
  fantasy: ["Fantasy", "Lichess", "icon"],
  celtic: ["Celtic", "Lichess", "icon"],
  chessnut: ["Chessnut", "Lichess", "icon"],
  rhosgfx: ["RhosGFX", "Lichess", "icon"],
  clay: ["Clay 3D", "自绘", "sculpt"],
};

function ensure(dir) {
  mkdirSync(dir, { recursive: true });
}

function complete(dir, files) {
  return files.every((f) => existsSync(join(dir, f)) && statSync(join(dir, f)).size > 40);
}

function svgToPng(svgText, dest) {
  const resvg = new Resvg(svgText, {
    fitTo: { mode: "width", value: SIZE },
    background: "rgba(0,0,0,0)",
  });
  writeFileSync(dest, resvg.render().asPng());
}

ensure(OUT);

const catalog = [];
function add(id, sourceHint) {
  const [name, source, style, layout] = NAMES[id];
  catalog.push({ id, name, source: sourceHint || source, style, ...(layout ? { layout } : {}) });
}

// --originals-only: regenerate only the original SVG sets in this repository and
// merge them into the existing catalog.json (Lichess/Clay inputs are not needed).
const ORIGINALS_ONLY = process.argv.includes("--originals-only");

// Lichess SVGs
for (const dirent of ORIGINALS_ONLY ? [] : readdirSync(SRC, { withFileTypes: true })) {
  if (!dirent.isDirectory()) continue;
  const id = dirent.name;
  if (!(id in NAMES) || id === "clay" || id === "nook_flat") continue;
  const srcDir = join(SRC, dirent.name);
  const files = Object.keys(LI_MAP).map((k) => `${k}.svg`);
  if (!complete(srcDir, files)) continue;
  for (const [from, to] of Object.entries(LI_MAP)) {
    const svg = readFileSync(join(srcDir, `${from}.svg`), "utf8");
    svgToPng(svg, join(OUT, `${id}__${to}.png`));
  }
  add(id, "Lichess");
  console.log("li", id);
}

// Clay 3D originals
if (!ORIGINALS_ONLY) {
  for (const color of ["white", "black"]) {
    for (const kind of ["pawn", "knight", "bishop", "rook", "queen", "king"]) {
      const name = `${color}_${kind}.png`;
      copyFileSync(join(CLAY, `${color}_${kind}.imageset`, name), join(OUT, `clay__${name}`));
    }
  }
  add("clay", "自绘");
  console.log("clay");
}

// Original vector sets are kept in the repository under artwork/<dir>/.
// Nook Flat is 64 x 72; the five "square" sets are 100 x 100. For the square
// sets the viewBox is shifted so the union bounding box of all twelve pieces is
// centred in the square; relative piece sizes and baselines are untouched.
const ORIGINAL_DIRS = {
  nook_flat: "nook-flat",
  nook_soft: "nook-soft",
  nook_crisp: "nook-crisp",
  nook_block: "nook-block",
  nook_mono: "nook-mono",
  nook_badge: "nook-badge",
};
const KINDS = ["pawn", "knight", "bishop", "rook", "queen", "king"];

function originalSvgs(dir) {
  const out = {};
  for (const color of ["white", "black"]) {
    for (const kind of KINDS) {
      const name = `${color}_${kind}`;
      out[name] = readFileSync(new URL(`../artwork/${dir}/${name}.svg`, import.meta.url), "utf8");
    }
  }
  return out;
}

function centredViewBox(svgs) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const svg of Object.values(svgs)) {
    const b = new Resvg(svg).getBBox();
    x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y);
    x1 = Math.max(x1, b.x + b.width); y1 = Math.max(y1, b.y + b.height);
  }
  return [(x0 + x1) / 2 - 50, (y0 + y1) / 2 - 50];
}

for (const [id, dir] of Object.entries(ORIGINAL_DIRS)) {
  const svgs = originalSvgs(dir);
  const square = NAMES[id][3] === "square";
  const [dx, dy] = square ? centredViewBox(svgs) : [0, 0];
  for (const [name, svg] of Object.entries(svgs)) {
    const text = square ? svg.replace(/viewBox="[^"]*"/, `viewBox="${dx.toFixed(2)} ${dy.toFixed(2)} 100 100"`) : svg;
    // Keep the committed Nook Flat PNGs untouched when only adding new sets.
    if (ORIGINALS_ONLY && id === "nook_flat") continue;
    svgToPng(text, join(OUT, `${id}__${name}.png`));
  }
  add(id);
  console.log("original", id);
}

const order = ["nook_flat", "nook_soft", "nook_crisp", "nook_block", "nook_mono", "nook_badge", "clay", "spatial", "rhosgfx", "celtic", "chessnut", "fantasy"];
catalog.sort((a, b) => {
  const ia = order.indexOf(a.id);
  const ib = order.indexOf(b.id);
  if (ia === -1 && ib === -1) return a.name.localeCompare(b.name);
  if (ia === -1) return 1;
  if (ib === -1) return -1;
  return ia - ib;
});

let sets = catalog;
if (ORIGINALS_ONLY) {
  const existing = JSON.parse(readFileSync(join(OUT, "catalog.json"), "utf8")).sets;
  const fresh = new Set(catalog.map((c) => c.id));
  const merged = [...catalog, ...existing.filter((c) => !fresh.has(c.id))];
  merged.sort((a, b) => {
    const ia = order.indexOf(a.id), ib = order.indexOf(b.id);
    if (ia === -1 && ib === -1) return 0;
    return ia === -1 ? 1 : ib === -1 ? -1 : ia - ib;
  });
  sets = merged;
}
writeFileSync(join(OUT, "catalog.json"), JSON.stringify({ defaultID: "nook_flat", sets }, null, 2));
console.log("catalog", sets.length);
