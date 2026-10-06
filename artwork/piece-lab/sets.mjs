// Original piece sets. Every shape is hand-authored geometry on a 100x100 grid.
export const THEMES = {
  white: { F: '#F7F8F6', S: '#2F3E46', D: '#2F3E46' },
  black: { F: '#3B4E58', S: '#0F1920', D: '#E8EEF1' },
};

const P = (pts) => pts.map((p) => p.join(',')).join(' ');
const poly = (pts) => `<polygon points="${P(pts)}"/>`;
const reg = (n, cx, cy, r, rot = -90) =>
  Array.from({ length: n }, (_, i) => {
    const a = ((rot + (360 / n) * i) * Math.PI) / 180;
    return [+(cx + r * Math.cos(a)).toFixed(2), +(cy + r * Math.sin(a)).toFixed(2)];
  });
const rect = (x, y, w, h, rx = 0) => `<rect x="${x}" y="${y}" width="${w}" height="${h}"${rx ? ` rx="${rx}"` : ''}/>`;
const circ = (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}"/>`;
const path = (d) => `<path d="${d}"/>`;

// union outline: draw all shapes thick in the outline colour, then fill on top
const U = (shapes, T, sw, join = 'round') =>
  `<g fill="${T.S}" stroke="${T.S}" stroke-width="${2 * sw}" stroke-linejoin="${join}" stroke-miterlimit="4">${shapes}</g><g fill="${T.F}">${shapes}</g>`;
const L = (d, T, w) =>
  d ? `<g fill="none" stroke="${T.D}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${d}</g>` : '';
const DOT = (d, T) => (d ? `<g fill="${T.D}">${d}</g>` : '');
const lines = (...a) => a.map((d) => `<path d="${d}"/>`).join('');

// ---------- 1. Soft Geometry ----------
const softKnight = 'M30 74Q30 60 42 52L26 58Q18 60 17 53Q17 46 24 40L33 30L38 14L47 25Q62 26 70 40Q76 54 72 74Z';
const soft = {
  id: 'soft', zh: '圆润几何', en: 'Soft Geometry',
  idea: '圆和圆角矩形搭成，软糖般的厚实剪影。',
  draw(k, T) {
    const base = rect(20, 73, 60, 11, 5.5);
    const sw = 2.5;
    const u = (s, d = '', dots = '') => U(s, T, sw) + L(d, T, 3) + DOT(dots, T);
    switch (k) {
      case 'pawn':
        return u(circ(50, 33, 13) + path('M40 73Q47 58 44 46H56Q53 58 60 73Z') + rect(37, 44, 26, 7, 3.5) + base);
      case 'rook':
        return u(rect(23, 19, 12, 22, 2.5) + rect(44, 19, 12, 22, 2.5) + rect(65, 19, 12, 22, 2.5) + rect(23, 36, 54, 9, 3) + rect(29, 44, 42, 31, 2) + base, lines('M31 45H69'));
      case 'queen':
        return u(
          path('M26 33L32 48L38 26L44 46L50 22L56 46L62 26L68 48L74 33L69 62H31Z') + rect(29, 59, 42, 10, 4) + base +
            [26, 38, 50, 62, 74].map((x, i) => circ(x, [30, 23, 19, 23, 30][i], 4.5)).join(''),
          lines('M33 64H67'));
      case 'king':
        return u(rect(46, 8, 8, 28, 2.5) + rect(37, 15, 26, 8, 2.5) + path('M28 73Q29 52 40 45H60Q71 52 72 73Z') + rect(35, 38, 30, 9, 4.5) + base, lines('M36 52H64'));
      case 'bishop':
        return u(path('M50 22Q70 36 66 54Q64 62 60 65H40Q36 62 34 54Q30 36 50 22Z') + circ(50, 16, 5.5) + rect(34, 62, 32, 9, 4.5) + base, lines('M57 32L44 46'));
      case 'knight':
        return u(path(softKnight) + base, lines('M50 32Q63 40 65 60'), circ(40, 36, 3.2) + circ(22, 49, 1.8));
    }
  },
};

// ---------- 2. Crisp Facets ----------
const crispKnight = [[30, 73], [31, 57], [42, 50], [24, 58], [15, 53], [17, 43], [32, 29], [35, 13], [46, 24], [60, 26], [73, 44], [72, 73]];
const crisp = {
  id: 'crisp', zh: '锐角切面', en: 'Crisp Facets',
  idea: '全部由直线切出：尖锐的城垛、王冠和马鬃。',
  draw(k, T) {
    const base = poly([[20, 84], [80, 84], [74, 73], [26, 73]]);
    const sw = 2.5;
    const u = (s, d = '', dots = '') => U(s, T, sw, 'miter') + L(d, T, 3) + DOT(dots, T);
    const tip = (x, y, r = 5.5) => poly([[x, y - r], [x + r, y], [x, y + r], [x - r, y]]);
    switch (k) {
      case 'pawn':
        return u(poly(reg(8, 50, 34, 14, -90 + 22.5)) + poly([[40, 73], [44, 47], [56, 47], [60, 73]]) + rect(36, 45, 28, 6) + base);
      case 'rook':
        return u(rect(23, 18, 12, 22) + rect(44, 18, 12, 22) + rect(65, 18, 12, 22) + rect(23, 36, 54, 8) + poly([[29, 44], [71, 44], [67, 73], [33, 73]]) + base, lines('M32 49H68'));
      case 'queen':
        return u(
          poly([[24, 34], [31, 52], [37, 28], [43.5, 50], [50, 24], [56.5, 50], [63, 28], [69, 52], [76, 34], [68, 63], [32, 63]]) +
            poly([[29, 63], [71, 63], [67, 70], [33, 70]]) + base +
            [24, 37, 50, 63, 76].map((x, i) => tip(x, [29, 22, 17, 22, 29][i], 4)).join(''),
          lines('M34 57H66'));
      case 'king':
        return u(rect(46, 8, 8, 28) + rect(37, 15, 26, 8) + poly([[26, 73], [33, 46], [67, 46], [74, 73]]) + poly([[35, 47], [39, 36], [61, 36], [65, 47]]) + base, lines('M36 56H64'));
      case 'bishop':
        return u(poly([[50, 22], [69, 46], [63, 65], [37, 65], [31, 46]]) + tip(50, 16, 6) + rect(34, 62, 32, 9) + base, lines('M58 31L43 48'));
      case 'knight':
        return u(poly(crispKnight) + base, lines('M50 29L64 46'), poly([[36, 33], [41, 36], [36, 40], [32, 36]]));
    }
  },
};

// ---------- 3. Bold Blocks ----------
const blockKnight = [[28, 72], [28, 58], [38, 52], [22, 58], [14, 52], [16, 41], [30, 30], [34, 13], [46, 24], [64, 28], [76, 48], [74, 72]];
const block = {
  id: 'block', zh: '厚重积木', en: 'Bold Blocks',
  idea: '最粗的轮廓和放大的关键部位，小屏幕上最醒目。',
  draw(k, T) {
    const base = rect(16, 71, 68, 13, 3);
    const sw = 4;
    const u = (s, d = '', dots = '') => U(s, T, sw) + L(d, T, 4.5) + DOT(dots, T);
    switch (k) {
      case 'pawn':
        return u(circ(50, 35, 16) + path('M36 71Q44 58 42 48H58Q56 58 64 71Z') + base);
      case 'rook':
        return u(rect(20, 17, 14, 22, 2) + rect(43, 17, 14, 22, 2) + rect(66, 17, 14, 22, 2) + rect(20, 33, 60, 12, 2) + rect(27, 44, 46, 28, 2) + base);
      case 'queen':
        return u(
          poly([[22, 34], [36, 56], [50, 28], [64, 56], [78, 34], [72, 66], [28, 66]]) + rect(25, 62, 50, 11, 3) + base +
            circ(22, 29, 7) + circ(50, 22, 7) + circ(78, 29, 7));
      case 'king':
        return u(rect(43, 6, 14, 34, 2) + rect(32, 14, 36, 13, 2) + path('M24 72Q24 50 36 42H64Q76 50 76 72Z') + base, lines('M36 55H64'));
      case 'bishop':
        return u(`<ellipse cx="50" cy="43" rx="19" ry="26"/>` + circ(50, 13, 7) + rect(33, 63, 34, 10, 3) + base, lines('M60 28L42 48'));
      case 'knight':
        return u(poly(blockKnight) + base, '', circ(40, 38, 4.5));
    }
  },
};

// ---------- 4. Monoline ----------
const monoKnight = 'M30 72Q30 58 42 51L27 58Q18 60 17 53Q17 45 25 39L33 30L37 15L46 25Q62 26 70 40Q77 54 72 72Z';
const mono = {
  id: 'mono', zh: '单线轮廓', en: 'Monoline',
  idea: '全部用同一粗细的线条画成，只留最少的填充。',
  draw(k, T) {
    const base = rect(22, 72, 56, 11, 3);
    const g = (s) => `<g fill="${T.F}" stroke="${T.S}" stroke-width="4" stroke-linejoin="round">${s}</g>`;
    const d = (x) => L(x, T, 4);
    const cross = (top) => path(`M45.5 ${top}H54.5V${top + 8}H64V${top + 17}H54.5V${top + 28}H45.5V${top + 17}H36V${top + 8}H45.5Z`);
    switch (k) {
      case 'pawn':
        return g(path('M38 72Q47 58 45 46H55Q53 58 62 72Z') + circ(50, 33, 12) + base);
      case 'rook':
        return g(path('M24 19H35V30H44V19H56V30H65V19H76V41H70V72H30V41H24Z') + base);
      case 'queen':
        return g(path('M30 72L26 34L32 50L38 28L44 48L50 24L56 48L62 28L68 50L74 34L70 72Z') + [26, 38, 50, 62, 74].map((x, i) => circ(x, [29, 23, 19, 23, 29][i], 3.8)).join('') + base) + d(lines('M34 61H66'));
      case 'king':
        return g(path('M30 72Q30 48 42 44H58Q70 48 70 72Z') + cross(7) + base) + d(lines('M38 57H62'));
      case 'bishop':
        return g(path('M50 21Q67 34 65 52Q64 62 59 66H41Q36 62 35 52Q33 34 50 21Z') + circ(50, 14, 4.5) + rect(37, 64, 26, 8, 3) + base) + d(lines('M57 32L45 46'));
      case 'knight':
        return g(path(monoKnight) + base) + d(lines('M50 32Q63 40 65 58')) + DOT(circ(40, 37, 2.8), T);
    }
  },
};

// ---------- 5. Badge Discs ----------
const badge = {
  id: 'badge', zh: '圆徽章', en: 'Badge Discs',
  idea: '每枚棋子都是一枚圆形徽章，里面只放一个醒目的符号。',
  draw(k, T) {
    const disc = `<circle cx="50" cy="50" r="38" fill="${T.F}" stroke="${T.S}" stroke-width="3"/>`;
    const gl = (s, cut = '') => disc + `<g fill="${T.D}">${s}</g>` + (cut ? `<g fill="none" stroke="${T.F}" stroke-width="3.5" stroke-linecap="round">${cut}</g>` : '');
    switch (k) {
      case 'pawn':
        return gl(circ(50, 36, 11) + path('M38 72Q46 57 44 49H56Q54 57 62 72Z') + rect(35, 47, 30, 6, 3) + rect(30, 69, 40, 6, 3));
      case 'rook':
        return gl(rect(29, 24, 11, 16, 1.5) + rect(44.5, 24, 11, 16, 1.5) + rect(60, 24, 11, 16, 1.5) + rect(29, 38, 42, 9, 1.5) + rect(33, 46, 34, 22) + rect(28, 66, 44, 7, 2));
      case 'queen':
        return gl(path('M27 36L35 55L39 30L45 53L50 26L55 53L61 30L65 55L73 36L68 66H32Z') + [27, 39, 50, 61, 73].map((x, i) => circ(x, [32, 26, 22, 26, 32][i], 4.2)).join('') + rect(31, 66, 38, 7, 2));
      case 'king':
        return gl(rect(46, 15, 8, 24, 2) + rect(38, 21, 24, 8, 2) + path('M30 73Q30 50 40 44H60Q70 50 70 73Z'), lines('M38 57H62'));
      case 'bishop':
        return gl(`<ellipse cx="50" cy="45" rx="13" ry="21"/>` + circ(50, 21, 4.5) + rect(36, 63, 28, 8, 3), lines('M57 34L44 48'));
      case 'knight':
        return gl(`<g transform="translate(17.5 15.5) scale(.7)">${path(softKnight)}${rect(20, 73, 60, 11, 5.5)}</g>`, '') + `<circle cx="${(17.5 + 40 * 0.7).toFixed(1)}" cy="${(15.5 + 36 * 0.7).toFixed(1)}" r="2.4" fill="${T.F}"/>`;
    }
  },
};

export const SETS = [soft, crisp, block, mono, badge];
export const KINDS = ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn'];
