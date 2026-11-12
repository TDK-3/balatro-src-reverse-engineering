#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
cd "$SCRIPT_DIR"

DIST_DIR="dist"
CACHE_DIR="cache"

echo "=== 1. Preparing build directories ==="
rm -rf "$DIST_DIR" "$CACHE_DIR"
mkdir -p "$DIST_DIR" "$CACHE_DIR"

echo "=== 2. Packaging universal Balatro.love ==="
zip -9 -r "${DIST_DIR}/Balatro.love" . \
    -x "*.git*" \
    -x "${DIST_DIR}/*" \
    -x "${CACHE_DIR}/*" \
    -x "*.sh" \
    -x "*.py" \
    -x "README.md" \
    -x ".gitignore"

echo "=== 3. Downloading LÖVE 11.5 desktop runtimes & love.js web player ==="
gh release download 11.5 \
    --repo love2d/love \
    --pattern "love-11.5-win64.zip" \
    --pattern "love-11.5-macos.zip" \
    --pattern "love-11.5-x86_64.AppImage" \
    --dir "$CACHE_DIR"

gh repo clone 2dengine/love.js "${CACHE_DIR}/lovejs" -- --depth 1

echo "=== 4. Building Windows (x64) release ==="
unzip -q "${CACHE_DIR}/love-11.5-win64.zip" -d "${CACHE_DIR}/win_extract"
WIN_ROOT=$(find "${CACHE_DIR}/win_extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)
cat "${WIN_ROOT}/love.exe" "${DIST_DIR}/Balatro.love" > "${WIN_ROOT}/Balatro.exe"
rm -f "${WIN_ROOT}/love.exe" "${WIN_ROOT}/lovec.exe"
(cd "${WIN_ROOT}" && zip -9 -r "../../../${DIST_DIR}/Balatro-Windows-x64.zip" .)

echo "=== 5. Building macOS (Universal) release ==="
unzip -q "${CACHE_DIR}/love-11.5-macos.zip" -d "${CACHE_DIR}/mac_extract"
mv "${CACHE_DIR}/mac_extract/love.app" "${CACHE_DIR}/mac_extract/Balatro.app"
cp "${DIST_DIR}/Balatro.love" "${CACHE_DIR}/mac_extract/Balatro.app/Contents/Resources/Balatro.love"
sed -i 's/>LÖVE</>Balatro</g' "${CACHE_DIR}/mac_extract/Balatro.app/Contents/Info.plist"
sed -i 's/org.love2d.love/com.balatro.oss/g' "${CACHE_DIR}/mac_extract/Balatro.app/Contents/Info.plist"
(cd "${CACHE_DIR}/mac_extract" && zip -9 -y -r "../../${DIST_DIR}/Balatro-macOS-Universal.zip" Balatro.app)

echo "=== 6. Building Linux (x86_64) release ==="
chmod +x "${CACHE_DIR}/love-11.5-x86_64.AppImage"
(cd "$CACHE_DIR" && "./love-11.5-x86_64.AppImage" --appimage-extract > /dev/null)
LOVE_BIN=$(find "${CACHE_DIR}/squashfs-root" -type f -name "love" | head -n 1)
cat "$LOVE_BIN" "${DIST_DIR}/Balatro.love" > "${CACHE_DIR}/squashfs-root/Balatro-x86_64"
chmod +x "${CACHE_DIR}/squashfs-root/Balatro-x86_64"

cat << 'EOF' > "${CACHE_DIR}/squashfs-root/AppRun"
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/Balatro-x86_64" "$@"
EOF
chmod +x "${CACHE_DIR}/squashfs-root/AppRun"
tar -czf "${DIST_DIR}/Balatro-Linux-x86_64.tar.gz" -C "${CACHE_DIR}/squashfs-root" .

echo "=== 7. Building Web (love.js 11.5) release ==="
WEB_DIR="${DIST_DIR}/Balatro-Web"
mkdir -p "$WEB_DIR"
cp -r "${CACHE_DIR}/lovejs/"* "$WEB_DIR/"
rm -rf "${WEB_DIR}/.git" "${WEB_DIR}/nogame.love"
cp "${DIST_DIR}/Balatro.love" "${WEB_DIR}/Balatro.love"

cat << 'EOF' > "${WEB_DIR}/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Balatro (love.js)</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <script src="player.js?g=Balatro.love&v=11.5&n=1"></script>
</body>
</html>
EOF
(cd "${DIST_DIR}" && zip -9 -r "Balatro-Web-lovejs.zip" "Balatro-Web")

echo "=== 8. Verifying build sizes ==="
rm -rf "$CACHE_DIR"
ls -lh "$DIST_DIR"

for file in "${DIST_DIR}/Balatro.love" "${DIST_DIR}/Balatro-Windows-x64.zip" "${DIST_DIR}/Balatro-macOS-Universal.zip" "${DIST_DIR}/Balatro-Linux-x86_64.tar.gz" "${DIST_DIR}/Balatro-Web-lovejs.zip"; do
    SIZE=$(stat -c%s "$file")
    if [ "$SIZE" -lt 1000000 ]; then
        echo "WARNING: $file is smaller than 1MB ($SIZE bytes). Check that game assets are present in the repo root!"
        exit 1
    fi
done

echo "All builds verified and complete!"
