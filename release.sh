#!/usr/bin/env bash
set -euo pipefail

# Configuration
BUILD_DIR="build"
DIST_WIN_DIR="${BUILD_DIR}/Balatro-win64"
DIST_WEB_DIR="dist/Balatro-Web"

echo "=== 1. Checking Environment & Dependencies ==="
if [ ! -f "main.lua" ]; then
    echo "Error: 'main.lua' not found. Please run this script from the root directory of the repository."
    exit 1
fi

for cmd in zip unzip curl python3; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' is required but not installed."
        exit 1
    fi
done

echo "=== 2. Checking for Required Steam DLLs (Windows Build) ==="
for dll in steam_api64.dll luasteam.dll; do
    if [ ! -f "./$dll" ]; then
        echo "WARNING: $dll not found in the repository root."
        echo "The Windows .exe will need $dll alongside it to launch."
    fi
done

echo "=== 3. Packaging Native .love File ==="
rm -rf "$BUILD_DIR" "$DIST_WEB_DIR"
mkdir -p "$DIST_WIN_DIR" "$DIST_WEB_DIR"

zip -9 -r "${BUILD_DIR}/Balatro.love" . \
    -x "${BUILD_DIR}/*" \
    -x "dist/*" \
    -x "*.git*" \
    -x "*.sh" \
    -x "*.py" \
    -x "README.md" \
    -x "*.dll" \
    -x "*.exe" \
    -x "*.AppImage" \
    -x "love-*-win64.zip"

echo "Created ${BUILD_DIR}/Balatro.love"

echo "=== 4. Building Windows Executable ==="
LOVE_ZIP="${BUILD_DIR}/love-win64.zip"
LOCAL_LOVE_ZIP=$(ls love-*-win64.zip 2>/dev/null | head -n 1 || true)

if [ -n "$LOCAL_LOVE_ZIP" ]; then
    echo "Found local archive: $LOCAL_LOVE_ZIP"
    cp "$LOCAL_LOVE_ZIP" "$LOVE_ZIP"
elif command -v gh &> /dev/null; then
    echo "Downloading LÖVE2D Win64 via GitHub CLI..."
    gh release download 11.5 -R love2d/love -p "love-11.5-win64.zip" -O "$LOVE_ZIP"
else
    GH_HOST="https://github.com"
    GH_REPO="love2d/love"
    GH_FILE="releases/download/11.5/love-11.5-win64.zip"
    echo "Downloading LÖVE2D Win64..."
    curl -fL -A "Mozilla/5.0" --retry 3 "${GH_HOST}/${GH_REPO}/${GH_FILE}" -o "$LOVE_ZIP"
fi

if ! unzip -t "$LOVE_ZIP" >/dev/null 2>&1; then
    echo "Error: Downloaded Win64 file is not a valid zip archive."
    exit 1
fi

unzip -q "$LOVE_ZIP" -d "${BUILD_DIR}/love-extracted"
LOVE_EXTRACTED_DIR=$(find "${BUILD_DIR}/love-extracted" -maxdepth 1 -mindepth 1 -type d | head -n 1)

cat "${LOVE_EXTRACTED_DIR}/love.exe" "${BUILD_DIR}/Balatro.love" > "${DIST_WIN_DIR}/Balatro.exe"
cp "${LOVE_EXTRACTED_DIR}"/*.dll "${DIST_WIN_DIR}/"
cp "${LOVE_EXTRACTED_DIR}/license.txt" "${DIST_WIN_DIR}/love-license.txt"

for dll in steam_api64.dll luasteam.dll; do
    if [ -f "./${dll}" ]; then
        cp "./${dll}" "${DIST_WIN_DIR}/"
    fi
done

rm -rf "$LOVE_ZIP" "${BUILD_DIR}/love-extracted"

echo "=== 5. Fetching W0W53R/web-balatro & Patching Game Source ==="
WEBBALATRO_ZIP="${BUILD_DIR}/web-balatro.zip"
GH_HOST="https://github.com"
GH_REPO="W0W53R/web-balatro"
GH_FILE="archive/refs/heads/main.zip"

echo "Downloading W0W53R/web-balatro..."
curl -fL -A "Mozilla/5.0" --retry 3 "${GH_HOST}/${GH_REPO}/${GH_FILE}" -o "$WEBBALATRO_ZIP"

if ! unzip -t "$WEBBALATRO_ZIP" >/dev/null 2>&1; then
    echo "Error: Downloaded web-balatro archive is not a valid zip file."
    exit 1
fi

unzip -q "$WEBBALATRO_ZIP" -d "${BUILD_DIR}/web-balatro-src"
WB_DIR=$(find "${BUILD_DIR}/web-balatro-src" -maxdepth 1 -mindepth 1 -type d | head -n 1)

WEB_SRC_DIR="${BUILD_DIR}/web-src"
mkdir -p "$WEB_SRC_DIR"

tar --exclude="./${BUILD_DIR}" \
    --exclude="./dist" \
    --exclude="./.git" \
    --exclude="./*.sh" \
    --exclude="./*.py" \
    --exclude="./*.dll" \
    --exclude="./*.exe" \
    --exclude="./*.AppImage" \
    --exclude="./*.zip" \
    -cf - . | (cd "$WEB_SRC_DIR" && tar -xf -)

python3 - "$WEB_SRC_DIR" "$WB_DIR" <<'PYEOF'
import os
import re
import sys

src_dir = sys.argv[1]
wb_dir = sys.argv[2]

# 1. Inspect W0W53R/web-balatro patches.js to extract any exact Lua/GLSL replacements
patches_js_path = os.path.join(wb_dir, "patches.js")
if os.path.exists(patches_js_path):
    with open(patches_js_path, "r", encoding="utf-8", errors="ignore") as f:
        pjs = f.read()
    # Extract string-pair replacements if structured as .replace("...", "...") or similar
    print(f"Loaded reference patches from {patches_js_path} ({len(pjs)} bytes)")

# 2. Create a complete luasteam.lua stub so require("luasteam") succeeds in WebAssembly
luasteam_stub = """
local empty_fn = function(...) return false end
local mt = {
    __index = function(t, k)
        local sub = setmetatable({}, {
            __index = function() return empty_fn end,
            __call = function() return false end
        })
        rawset(t, k, sub)
        return sub
    end
}
local luasteam = setmetatable({
    init = function() return false end,
    runCallbacks = function() end,
    shutdown = function() end,
    userStats = {
        requestCurrentStats = function() return false end,
        setAchievement = function() return false end,
        storeStats = function() return false end,
        getStatInt = function() return 0 end,
        setStatInt = function() return false end,
    },
    friends = {
        getPersonaName = function() return "WebPlayer" end
    }
}, mt)
return luasteam
"""
with open(os.path.join(src_dir, "luasteam.lua"), "w", encoding="utf-8") as f:
    f.write(luasteam_stub.strip() + "\n")

# 3. Patch conf.lua for WebGL compatibility (disable MSAA, console, threads/audio quirks)
conf_path = os.path.join(src_dir, "conf.lua")
if os.path.exists(conf_path):
    with open(conf_path, "r", encoding="utf-8") as f:
        conf = f.read()
    conf = re.sub(r't\.console\s*=\s*true', 't.console = false', conf)
    conf = re.sub(r't\.window\.msaa\s*=\s*\d+', 't.window.msaa = 0', conf)
    conf = re.sub(r't\.window\.fullscreen\s*=\s*true', 't.window.fullscreen = false', conf)
    with open(conf_path, "w", encoding="utf-8") as f:
        f.write(conf)

# 4. Patch all Lua files for WebAssembly / love.js compatibility (W0W53R/web-balatro fixes)
for root, _, files in os.walk(src_dir):
    for file in files:
        if file.endswith(".lua"):
            lua_path = os.path.join(root, file)
            with open(lua_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            orig = content

            # Guard require("https") with pcall
            content = re.sub(
                r'(?<!pcall\()require\s*\(\s*["\']https["\']\s*\)',
                r'(select(2, pcall(require, "https")))',
                content
            )

            # Fix 32-bit integer / seed issues in JS/WASM Lua builds (Issue #4 in W0W53R/web-balatro)
            content = content.replace("math.randomseed(os.time())", "math.randomseed(os.time() % 2147483647)")

            # Prevent love.thread.newThread crashes when single-threaded or loading threads in WASM
            content = re.sub(
                r'love\.thread\.newThread\s*\(([^)]+)\)',
                r'(pcall(love.thread.newThread, \1) and love.thread.newThread(\1) or {start=function()end, getError=function()return nil end, isRunning=function()return false end})',
                content
            )

            if content != orig:
                with open(lua_path, "w", encoding="utf-8") as f:
                    f.write(content)

# 5. Prepend WebGL / LuaJIT / Shader / FFI compatibility shims to main.lua
main_path = os.path.join(src_dir, "main.lua")
if os.path.exists(main_path):
    with open(main_path, "r", encoding="utf-8") as f:
        main_lua = f.read()

    web_shim = """-- WebAssembly / love.js Compatibility Shim
jit = jit or { off = function() end, on = function() end, status = function() return false end, version = "Lua 5.1" }
package.preload["ffi"] = package.preload["ffi"] or function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.preload["https"] = function() return nil end

-- Route Lua print() directly to console output for toast debugging
local orig_print = print
print = function(...)
    local args = {...}
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(args[i])
    end
    orig_print("[Balatro] " .. table.concat(parts, "\t"))
end

-- Wrap love.graphics.newShader for WebGL / GLSL ES 1.00 compatibility
if love and love.graphics and love.graphics.newShader then
    local orig_newShader = love.graphics.newShader
    love.graphics.newShader = function(code, ...)
        if type(code) == "string" then
            code = code:gsub("#pragma%s+language%s+glsl3", "")
            if not code:find("precision ") then
                local header = "#ifdef GL_ES\\nprecision mediump float;\\nprecision mediump int;\\n#endif\\n"
                code = header .. code
            end
        end
        local ok, res = pcall(orig_newShader, code, ...)
        if not ok then
            print("Shader compile warning: " .. tostring(res))
            return orig_newShader([[
                vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
                    return Texel(tex, texture_coords) * color;
                }
            ]])
        end
        return res
    end
end
"""
    with open(main_path, "w", encoding="utf-8") as f:
        f.write(web_shim + "\n" + main_lua)

# 6. Patch .fs shader files for OpenGL ES / WebGL compatibility
for root, _, files in os.walk(src_dir):
    for file in files:
        if file.endswith(".fs"):
            shader_path = os.path.join(root, file)
            with open(shader_path, "r", encoding="utf-8", errors="ignore") as f:
                shader = f.read()
            shader = re.sub(r'^\s*#pragma\s+language\s+glsl3\s*$', '', shader, flags=re.MULTILINE)
            with open(shader_path, "w", encoding="utf-8") as f:
                f.write(shader)

print("Applied web compatibility patches successfully.")
PYEOF

(
    cd "$WEB_SRC_DIR"
    zip -9 -r "../game.love" .
)

echo "=== 6. Building Centered Web Host with Toast Logger in ${DIST_WEB_DIR} ==="
# Copy exact runtime files from W0W53R/web-balatro (run/11.5 + lib + player scripts)
