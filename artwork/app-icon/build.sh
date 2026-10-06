#!/bin/zsh
# Regenerates the Icon Composer bundle assets from the SVG sources.
set -e
cd "$(dirname "$0")"
OUT=../../ichess/ichess/AppIcon.icon
mkdir -p "$OUT/Assets"
rsvg-convert -w 1024 -h 1024 background.svg -o "$OUT/Assets/background.png"
rsvg-convert -w 1024 -h 1024 knight.svg -o "$OUT/Assets/knight.png"
cp icon.json "$OUT/icon.json"
