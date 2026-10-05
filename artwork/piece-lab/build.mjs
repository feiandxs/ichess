import fs from 'fs';
import { SETS, KINDS, THEMES } from './sets.mjs';
let sym = '';
const meta = [];
for (const s of SETS) {
  meta.push({ id: s.id, zh: s.zh, en: s.en, idea: s.idea });
  for (const c of ['white', 'black']) for (const k of KINDS)
    sym += `<symbol id="p-${s.id}-${c}-${k}" viewBox="0 0 100 100">${s.draw(k, THEMES[c])}</symbol>`;
}
const nd = '/Users/feiandxs/workspace/ichess/artwork/nook-flat/';
meta.unshift({ id: 'nook-flat', zh: 'Nook 扁平（现用）', en: 'Nook Flat · current', idea: '应用目前使用的原创套装，作为对照基准。' });
let ns = '';
for (const c of ['white', 'black']) for (const k of KINDS) {
  const inner = fs.readFileSync(`${nd}${c}_${k}.svg`, 'utf8').replace(/<svg[^>]*>/, '').replace(/<\/svg>/, '').replace(/<title>.*?<\/title>/, '');
  ns += `<symbol id="p-nook-flat-${c}-${k}" viewBox="-4 0 72 72">${inner}</symbol>`;
}
let h = fs.readFileSync('template.html', 'utf8').replace('__SYMBOLS__', ns + sym).replace('__META__', JSON.stringify(meta));
h = h.replace('--muted: #56697 3', '');
fs.writeFileSync('piece-lab.html', h);
console.log(h.length);
