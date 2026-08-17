#!/usr/bin/env bash
# Regenerate the macOS app icon from tools/icon.svg into the asset catalog.
#
#   ./tools/make_appicon.sh
#
# Requires librsvg (brew install librsvg). Each size is rasterised straight from
# the vector rather than downscaled, so the small sizes stay crisp.
set -euo pipefail

cd "$(dirname "$0")/.."
SVG="tools/icon.svg"
OUT="macos/App/Assets.xcassets/AppIcon.appiconset"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found — brew install librsvg" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$OUT"/*.png

# "<point size> <scale> <pixel size>"
while read -r pt scale px; do
  [ "$scale" = "1x" ] && name="icon_${pt}x${pt}.png" || name="icon_${pt}x${pt}@2x.png"
  rsvg-convert -w "$px" -h "$px" "$SVG" -o "$OUT/$name"
  echo "  $name  (${px}px)"
done <<'SIZES'
16 1x 16
16 2x 32
32 1x 32
32 2x 64
128 1x 128
128 2x 256
256 1x 256
256 2x 512
512 1x 512
512 2x 1024
SIZES

cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Wrote $OUT"
