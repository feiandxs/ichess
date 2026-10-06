# App icon source

Full-bleed artwork for the Icon Composer bundle `ichess/ichess/AppIcon.icon`
(the system applies the squircle mask; do not pre-round or add a border).

- `background.svg`: 4x4 checkerboard filling the 1024 canvas.
- `knight.svg`: white knight with dark outline, inside the ~80% safe area.
- `icon.json`: Icon Composer layer description (knight above background).
- `build.sh`: renders PNG layers (needs `rsvg-convert`) into the bundle.
