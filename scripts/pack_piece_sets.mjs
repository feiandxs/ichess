#!/usr/bin/env node
import { Resvg } from "@resvg/resvg-js";
import { mkdirSync, readdirSync, readFileSync, writeFileSync, copyFileSync, existsSync, statSync } from "fs";
import { join, basename } from "path";

const SRC = "/tmp/chess-compare";
const CLAY = "/Users/feiandxs/workspace/ichess/ichess/ichess/Assets.xcassets/Pieces";
const OUT = "/Users/feiandxs/workspace/ichess/ichess/ichess/PieceSets";
const SIZE = 256;

const CC_MAP = {
  wp: "white_pawn", wn: "white_knight", wb: "white_bishop",
  wr: "white_rook", wq: "white_queen", wk: "white_king",
  bp: "black_pawn", bn: "black_knight", bb: "black_bishop",
  br: "black_rook", bq: "black_queen", bk: "black_king",
};
const LI_MAP = {
  wP: "white_pawn", wN: "white_knight", wB: "white_bishop",
  wR: "white_rook", wQ: "white_queen", wK: "white_king",
  bP: "black_pawn", bN: "black_knight", bB: "black_bishop",
  bR: "black_rook", bQ: "black_queen", bK: "black_king",
};

const NAMES = {
  neo: ["Neo", "Chess.com", "icon"],
  clay: ["Clay 3D", "自绘", "sculpt"],
  geometric: ["Geometric", "自绘 SVG", "icon"],
  spatial: ["Spatial", "Lichess", "icon"],
  fresca: ["Fresca", "Lichess", "icon"],
  cases: ["Cases", "Chess.com", "icon"],
  icy_sea: ["Icy Sea", "Chess.com", "icon"],
  bases: ["Bases", "Chess.com", "icon"],
  modern: ["Modern", "Chess.com", "icon"],
  dash: ["Dash", "Chess.com", "icon"],
  caliente: ["Caliente", "Lichess", "icon"],
  rhosgfx: ["RhosGFX", "Lichess", "icon"],
  icpieces: ["ICpieces", "Lichess", "icon"],
  light: ["Light", "Chess.com", "icon"],
  shapes: ["Shapes", "Lichess", "icon"],
  companion: ["Companion", "Lichess", "icon"],
  california: ["California", "Lichess", "icon"],
  cooke: ["Cooke", "Lichess", "icon"],
  papercut: ["Papercut", "Lichess", "icon"],
  bubblegum: ["Bubblegum", "Chess.com", "icon"],
  "8_bit": ["8-bit", "Chess.com", "icon"],
  pixel: ["Pixel", "Lichess", "icon"],
  lolz: ["Lolz", "Chess.com", "icon"],
  "3d_chesskid": ["ChessKid", "Chess.com", "icon"],
  horsey: ["Horsey", "Lichess", "icon"],
  anarcandy: ["Anarcandy", "Lichess", "icon"],
  xkcd: ["xkcd", "Lichess", "icon"],
  graffiti: ["Graffiti", "Chess.com", "icon"],
  totoy: ["Totoy", "Lichess", "icon"],
  "3d_staunton": ["3D Staunton", "Chess.com", "sculpt"],
  "3d_plastic": ["3D Plastic", "Chess.com", "sculpt"],
  "3d_wood": ["3D Wood", "Chess.com", "sculpt"],
  cburnett: ["Cburnett", "Lichess", "icon"],
  merida: ["Merida", "Lichess", "icon"],
  alpha: ["Alpha", "Chess.com", "icon"],
  li_alpha: ["Alpha (Lichess)", "Lichess", "icon"],
  maestro: ["Maestro", "Lichess", "icon"],
  staunty: ["Staunty", "Lichess", "icon"],
  chess7: ["Chess7", "Lichess", "icon"],
  leipzig: ["Leipzig", "Lichess", "icon"],
  kosal: ["Kosal", "Lichess", "icon"],
  gioco: ["Gioco", "Lichess", "icon"],
  chessnut: ["Chessnut", "Lichess", "icon"],
  fantasy: ["Fantasy", "Lichess", "icon"],
  firi: ["Firi", "Lichess", "icon"],
  cardinal: ["Cardinal", "Lichess", "icon"],
  dubrovny: ["Dubrovny", "Lichess", "icon"],
  reillycraig: ["Reillycraig", "Lichess", "icon"],
  tatiana: ["Tatiana", "Lichess", "icon"],
  governor: ["Governor", "Lichess", "icon"],
  celtic: ["Celtic", "Lichess", "icon"],
  mpchess: ["MP Chess", "Lichess", "icon"],
  pirouetti: ["Pirouetti", "Lichess", "icon"],
  letter: ["Letter", "Lichess", "icon"],
  disguised: ["Disguised", "Lichess", "icon"],
  kiwen_suwi: ["Kiwen Suwi", "Lichess", "icon"],
  riohacha: ["Riohacha", "Lichess", "icon"],
  wood: ["Wood", "Chess.com", "icon"],
  marble: ["Marble", "Chess.com", "icon"],
  glass: ["Glass", "Chess.com", "icon"],
  metal: ["Metal", "Chess.com", "icon"],
  neo_wood: ["Neo Wood", "Chess.com", "icon"],
  nature: ["Nature", "Chess.com", "icon"],
  ocean: ["Ocean", "Chess.com", "icon"],
  sky: ["Sky", "Chess.com", "icon"],
  space: ["Space", "Chess.com", "icon"],
  neon: ["Neon", "Chess.com", "icon"],
  book: ["Book", "Chess.com", "icon"],
  game_room: ["Game Room", "Chess.com", "icon"],
  gothic: ["Gothic", "Chess.com", "icon"],
  maya: ["Maya", "Chess.com", "icon"],
  tigers: ["Tigers", "Chess.com", "icon"],
  newspaper: ["Newspaper", "Chess.com", "icon"],
  classic: ["Classic", "Chess.com", "icon"],
  club: ["Club", "Chess.com", "icon"],
  condal: ["Condal", "Chess.com", "icon"],
  tournament: ["Tournament", "Chess.com", "icon"],
  vintage: ["Vintage", "Chess.com", "icon"],
  cc_alpha: ["Alpha (Chess.com)", "Chess.com", "icon"],
};

function pretty(id) {
  if (NAMES[id]) return NAMES[id];
  const name = id.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  return [name, "imported", "icon"];
}

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
  const [name, source, style] = pretty(id);
  catalog.push({ id, name, source: sourceHint || source, style });
}

// Chess.com PNGs
for (const dirent of readdirSync(SRC, { withFileTypes: true })) {
  if (!dirent.isDirectory() || !dirent.name.startsWith("cc_")) continue;
  const id = dirent.name.slice(3);
  const srcDir = join(SRC, dirent.name);
  const files = Object.keys(CC_MAP).map((k) => `${k}.png`);
  if (!complete(srcDir, files)) continue;
  for (const [from, to] of Object.entries(CC_MAP)) {
    copyFileSync(join(srcDir, `${from}.png`), join(OUT, `${id}__${to}.png`));
  }
  add(id, "Chess.com");
  console.log("cc", id);
}

// Lichess SVGs
for (const dirent of readdirSync(SRC, { withFileTypes: true })) {
  if (!dirent.isDirectory()) continue;
  if (dirent.name.startsWith("cc_") || dirent.name.endsWith("_png")) continue;
  let id = dirent.name === "kiwen-suwi" ? "kiwen_suwi" : dirent.name;
  const srcDir = join(SRC, dirent.name);
  const files = Object.keys(LI_MAP).map((k) => `${k}.svg`);
  if (!complete(srcDir, files)) continue;
  if (existsSync(join(OUT, `${id}__white_pawn.png`))) id = `li_${id}`;
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

// Geometric: restyle cburnett SVG (Neo palette, thicker stroke)
{
  const srcDir = join(SRC, "cburnett");
  if (complete(srcDir, Object.keys(LI_MAP).map((k) => `${k}.svg`))) {
    for (const [from, to] of Object.entries(LI_MAP)) {
      let svg = readFileSync(join(srcDir, `${from}.svg`), "utf8");
      const isWhite = from.startsWith("w");
      const fill = isWhite ? "#F3F6F8" : "#5C6B74";
      const stroke = isWhite ? "#3A4A52" : "#1C2428";
      svg = svg
        .replaceAll('fill="#fff"', `fill="${fill}"`)
        .replaceAll('fill="#ffffff"', `fill="${fill}"`)
        .replaceAll('fill="#000"', `fill="${fill}"`)
        .replaceAll("stroke-width=\"1.5\"", "stroke-width=\"2.15\"")
        .replaceAll("stroke=\"#000\"", `stroke="${stroke}"`);
      if (isWhite && !svg.includes("fill=")) {
        svg = svg.replace("<path ", `<path fill="${fill}" `);
      }
      svgToPng(svg, join(OUT, `geometric__${to}.png`));
    }
    add("geometric", "自绘 SVG");
    console.log("geometric");
  }
}

const order = [
  "neo", "geometric", "clay", "spatial", "fresca", "cases", "icy_sea", "bases",
  "caliente", "rhosgfx", "modern", "dash",
];
catalog.sort((a, b) => {
  const ia = order.indexOf(a.id);
  const ib = order.indexOf(b.id);
  if (ia === -1 && ib === -1) return a.name.localeCompare(b.name);
  if (ia === -1) return 1;
  if (ib === -1) return -1;
  return ia - ib;
});

writeFileSync(join(OUT, "catalog.json"), JSON.stringify({ defaultID: "neo", sets: catalog }, null, 2));
console.log("catalog", catalog.length);
