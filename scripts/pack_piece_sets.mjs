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
  nook_flat: ["Nook Flat", "自绘 SVG", "icon"],
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
  const [name, source, style] = NAMES[id];
  catalog.push({ id, name, source: sourceHint || source, style });
}

// Lichess SVGs
for (const dirent of readdirSync(SRC, { withFileTypes: true })) {
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
{
  for (const color of ["white", "black"]) {
    for (const kind of ["pawn", "knight", "bishop", "rook", "queen", "king"]) {
      const name = `${color}_${kind}.png`;
      copyFileSync(join(CLAY, `${color}_${kind}.imageset`, name), join(OUT, `clay__${name}`));
    }
  }
  add("clay", "自绘");
  console.log("clay");
}

// Original Nook Flat vectors are kept in the repository.
for (const color of ["white", "black"]) {
  for (const kind of ["pawn", "knight", "bishop", "rook", "queen", "king"]) {
    const name = `${color}_${kind}`;
    const svg = readFileSync(new URL(`../artwork/nook-flat/${name}.svg`, import.meta.url), "utf8");
    svgToPng(svg, join(OUT, `nook_flat__${name}.png`));
  }
}
add("nook_flat");

const order = ["nook_flat", "spatial", "clay", "rhosgfx", "celtic", "chessnut", "fantasy"];
catalog.sort((a, b) => {
  const ia = order.indexOf(a.id);
  const ib = order.indexOf(b.id);
  if (ia === -1 && ib === -1) return a.name.localeCompare(b.name);
  if (ia === -1) return 1;
  if (ib === -1) return -1;
  return ia - ib;
});

writeFileSync(join(OUT, "catalog.json"), JSON.stringify({ defaultID: "nook_flat", sets: catalog }, null, 2));
console.log("catalog", catalog.length);
