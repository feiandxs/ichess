import fs from 'fs';
import { SETS, KINDS, THEMES } from './sets.mjs';
const svg = (inner, title) => `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 100 100">\n  <title>${title}</title>\n  ${inner}\n</svg>\n`;
let sheet = '<body style="margin:0;font:12px sans-serif">';
for (const s of SETS) {
  fs.mkdirSync(`sets/${s.id}`, { recursive: true });
  sheet += `<div style="display:flex;flex-wrap:wrap;width:1400px">`;
  for (const c of ['white', 'black']) for (const k of KINDS) {
    const inner = s.draw(k, THEMES[c]);
    fs.writeFileSync(`sets/${s.id}/${c}_${k}.svg`, svg(inner, `${s.en} - ${c} ${k}`));
    sheet += `<svg width="110" height="110" viewBox="0 0 100 100" style="background:${c==='white'?'#E8EEF2':'#B0C4CE'}">${inner}</svg><svg width="110" height="110" viewBox="0 0 100 100" style="background:#16232B">${inner}</svg>`;
  }
  sheet += `<svg width="40" height="40" viewBox="0 0 100 100" style="background:#E8EEF2">${s.draw('knight',THEMES.white)}</svg></div><hr>`;
}
fs.writeFileSync('sheet.html', sheet);
// nook flat
fs.mkdirSync('sets/nook-flat', { recursive: true });
for (const f of fs.readdirSync('/Users/feiandxs/workspace/ichess/artwork/nook-flat')) if (f.endsWith('.svg')) fs.copyFileSync('/Users/feiandxs/workspace/ichess/artwork/nook-flat/' + f, 'sets/nook-flat/' + f);
