#!/usr/bin/env bash
set -euo pipefail

# Configuration
BUILD_DIR="dist"
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

patches_js_path = os.path.join(wb_dir, "patches.js")
if os.path.exists(patches_js_path):
    with open(patches_js_path, "r", encoding="utf-8", errors="ignore") as f:
        pjs = f.read()
    pairs = re.findall(r'\.replace\(\s*(["\'`])((?:\\.|(?!\1).)*)\1\s*,\s*(["\'`])((?:\\.|(?!\3).)*)\3\s*\)', pjs)
    applied_ref = 0
    for q1, old_raw, q2, new_raw in pairs:
        try:
            old_str = bytes(old_raw, "utf-8").decode("unicode_escape")
            new_str = bytes(new_raw, "utf-8").decode("unicode_escape")
        except Exception:
            old_str, new_str = old_raw, new_raw
        if len(old_str) < 4:
            continue
        for root, _, files in os.walk(src_dir):
            for file in files:
                if file.endswith((".lua", ".fs", ".vs")):
                    fpath = os.path.join(root, file)
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                        txt = f.read()
                    if old_str in txt:
                        txt = txt.replace(old_str, new_str)
                        with open(fpath, "w", encoding="utf-8") as f:
                            f.write(txt)
                        applied_ref += 1
    print(f"Applied {applied_ref} reference patch replacements from patches.js")

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

conf_path = os.path.join(src_dir, "conf.lua")
if os.path.exists(conf_path):
    with open(conf_path, "r", encoding="utf-8") as f:
        conf = f.read()
    conf = re.sub(r't\.console\s*=\s*true', 't.console = false', conf)
    conf = re.sub(r't\.window\.msaa\s*=\s*\d+', 't.window.msaa = 0', conf)
    conf = re.sub(r't\.window\.fullscreen\s*=\s*true', 't.window.fullscreen = false', conf)
    with open(conf_path, "w", encoding="utf-8") as f:
        f.write(conf)

for root, _, files in os.walk(src_dir):
    for file in files:
        if file.endswith(".lua"):
            lua_path = os.path.join(root, file)
            with open(lua_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            orig = content
            content = re.sub(
                r'(?<!pcall\()require\s*\(\s*["\']https["\']\s*\)',
                r'(select(2, pcall(require, "https")))',
                content
            )
            content = content.replace("math.randomseed(os.time())", "math.randomseed(os.time() % 2147483647)")
            if content != orig:
                with open(lua_path, "w", encoding="utf-8") as f:
                    f.write(content)

main_path = os.path.join(src_dir, "main.lua")
if os.path.exists(main_path):
    with open(main_path, "r", encoding="utf-8") as f:
        main_lua = f.read()

    web_shim = """-- WebAssembly / love.min.js Compatibility Shim
jit = jit or { off = function() end, on = function() end, status = function() return false end, version = "Lua 5.1" }
package.preload["ffi"] = package.preload["ffi"] or function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.preload["https"] = function() return nil end

local orig_print = print
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    orig_print("[Balatro] " .. table.concat(parts, "\t"))
end

if love and love.graphics and love.graphics.newShader then
    local orig_newShader = love.graphics.newShader
    local function patch_shader_src(src)
        if type(src) ~= "string" then return src end
        -- If src is a file path ending in .fs/.vs, read its contents via love.filesystem
        if not src:find("\\n") and src:match("%.[fv]s$") and love.filesystem.getInfo(src) then
            local file_data = love.filesystem.read(src)
            if file_data then src = file_data end
        end
        src = src:gsub("#pragma%s+language%s+glsl3", "")
        if not src:find("precision ") then
            local header = "#ifdef GL_ES\\nprecision highp float;\\nprecision highp int;\\n#endif\\n"
            src = header .. src
        end
        return src
    end

    love.graphics.newShader = function(code, code2, ...)
        local patched1 = patch_shader_src(code)
        local patched2 = code2 and patch_shader_src(code2) or nil
        local ok, res
        if patched2 then
            ok, res = pcall(orig_newShader, patched1, patched2, ...)
        else
            ok, res = pcall(orig_newShader, patched1, ...)
        end
        if not ok then
            print("Shader fallback triggered: " .. tostring(res))
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
    zip -9 -r "../Balatro.love" .
)

echo "=== 6. Building Centered 2dengine/love.min.js Host in ${DIST_WEB_DIR} ==="
cp -r "${WB_DIR}/run/11.5/"* "${DIST_WEB_DIR}/"
if [ -d "${WB_DIR}/lib" ]; then
    cp -r "${WB_DIR}/lib" "${DIST_WEB_DIR}/"
fi
for jsfile in player.js runVersion.js loadVersion.js single_file.js patches.js; do
    if [ -f "${WB_DIR}/${jsfile}" ]; then
        cp "${WB_DIR}/${jsfile}" "${DIST_WEB_DIR}/"
    fi
done

cp "${BUILD_DIR}/Balatro.love" "${DIST_WEB_DIR}/Balatro.love"

cat <<'EOF' > "${DIST_WEB_DIR}/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Balatro</title>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    html, body {
      width: 100%;
      height: 100%;
      background-color: #0e1116;
      display: flex;
      justify-content: center;
      align-items: center;
      overflow: hidden;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      color: #ffffff;
    }
    #game-container {
      width: 100vw;
      height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      position: relative;
    }
    canvas {
      display: block;
      margin: auto;
      max-width: 100vw;
      max-height: 100vh;
      aspect-ratio: 16 / 9;
      object-fit: contain;
      box-shadow: 0 12px 40px rgba(0, 0, 0, 0.75);
      background: #000;
    }
    #status {
      position: absolute;
      z-index: 10;
      font-size: 1.05rem;
      letter-spacing: 0.03em;
      background: rgba(14, 17, 22, 0.88);
      border: 1px solid rgba(255, 255, 255, 0.12);
      padding: 12px 20px;
      border-radius: 8px;
      pointer-events: none;
    }
    #toast-container {
      position: fixed;
      bottom: 16px;
      right: 16px;
      z-index: 9999;
      display: flex;
      flex-direction: column;
      gap: 8px;
      max-width: 440px;
      width: calc(100vw - 32px);
      max-height: 55vh;
      overflow-y: auto;
      pointer-events: none;
    }
    .toast {
      pointer-events: auto;
      background: rgba(18, 22, 30, 0.94);
      backdrop-filter: blur(6px);
      border-left: 4px solid #3b82f6;
      border-top: 1px solid rgba(255, 255, 255, 0.1);
      border-right: 1px solid rgba(255, 255, 255, 0.1);
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
      color: #f1f5f9;
      padding: 10px 14px;
      border-radius: 6px;
      font-size: 12px;
      line-height: 1.4;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      word-break: break-word;
      box-shadow: 0 6px 20px rgba(0, 0, 0, 0.55);
      opacity: 1;
      transition: opacity 0.35s ease, transform 0.35s ease;
    }
    .toast.log {
      border-left-color: #3b82f6;
    }
    .toast.warn {
      border-left-color: #f59e0b;
      background: rgba(38, 28, 12, 0.95);
      color: #fef3c7;
    }
    .toast.error {
      border-left-color: #ef4444;
      background: rgba(42, 14, 18, 0.96);
      color: #fee2e2;
    }
    .toast-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 10px;
      font-weight: 700;
      text-transform: uppercase;
      margin-bottom: 6px;
    }
    .toast-meta {
      display: flex;
      align-items: center;
      gap: 8px;
      opacity: 0.75;
    }
    .toast-copy-btn {
      background: rgba(255, 255, 255, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.2);
      color: #ffffff;
      border-radius: 4px;
      padding: 2px 7px;
      font-size: 10px;
      font-family: inherit;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.15s ease, border-color 0.15s ease;
    }
    .toast-copy-btn:hover {
      background: rgba(255, 255, 255, 0.22);
      border-color: rgba(255, 255, 255, 0.4);
    }
    .toast-copy-btn.copied {
      background: rgba(34, 197, 94, 0.25);
      border-color: rgba(34, 197, 94, 0.6);
      color: #86efac;
    }
    .toast.fade-out {
      opacity: 0;
      transform: translateY(8px);
    }
  </style>
</head>
<body>
  <div id="game-container">
    <div id="status">Initializing runtime...</div>
    <canvas id="canvas" oncontextmenu="event.preventDefault()"></canvas>
  </div>
  <div id="toast-container"></div>

  <script type="text/javascript">
    (function() {
      var container = document.getElementById('toast-container');
      var origLog = console.log.bind(console);
      var origWarn = console.warn.bind(console);
      var origError = console.error.bind(console);

      function formatArgs(args) {
        return Array.prototype.slice.call(args).map(function(arg) {
          if (arg instanceof Error) {
            return arg.stack || arg.message || String(arg);
          }
          if (typeof arg === 'object' && arg !== null) {
            try {
              return JSON.stringify(arg);
            } catch (e) {
              return String(arg);
            }
          }
          return String(arg);
        }).join(' ');
      }

      function showToast(level, args) {
        var msg = formatArgs(args);
        if (!msg) return;

        var toast = document.createElement('div');
        toast.className = 'toast ' + level;

        var header = document.createElement('div');
        header.className = 'toast-header';

        var meta = document.createElement('div');
        meta.className = 'toast-meta';
        var time = new Date().toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
        meta.innerHTML = '<span>' + level + '</span><span>' + time + '</span>';

        var copyBtn = document.createElement('button');
        copyBtn.type = 'button';
        copyBtn.className = 'toast-copy-btn';
        copyBtn.textContent = 'Copy';
        copyBtn.title = 'Copy message';
        copyBtn.addEventListener('click', function(e) {
          e.stopPropagation();
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(msg).then(function() {
              copyBtn.textContent = 'Copied';
              copyBtn.classList.add('copied');
              setTimeout(function() {
                copyBtn.textContent = 'Copy';
                copyBtn.classList.remove('copied');
              }, 1500);
            });
          } else {
            var ta = document.createElement('textarea');
            ta.value = msg;
            ta.style.position = 'fixed';
            ta.style.opacity = '0';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
            copyBtn.textContent = 'Copied';
            copyBtn.classList.add('copied');
            setTimeout(function() {
              copyBtn.textContent = 'Copy';
              copyBtn.classList.remove('copied');
            }, 1500);
          }
        });

        header.appendChild(meta);
        header.appendChild(copyBtn);

        var body = document.createElement('div');
        body.textContent = msg;

        toast.appendChild(header);
        toast.appendChild(body);
        container.appendChild(toast);

        while (container.children.length > 14) {
          container.removeChild(container.firstChild);
        }

        var duration = level === 'error' ? 30000 : (level === 'warn' ? 20000 : 15000);
        setTimeout(function() {
          toast.classList.add('fade-out');
          setTimeout(function() {
            if (toast.parentNode) toast.parentNode.removeChild(toast);
          }, 350);
        }, duration);
      }

      console.log = function() {
        origLog.apply(console, arguments);
        showToast('log', arguments);
      };

      console.warn = function() {
        origWarn.apply(console, arguments);
        showToast('warn', arguments);
      };

      console.error = function() {
        origError.apply(console, arguments);
        showToast('error', arguments);
      };

      window.addEventListener('error', function(e) {
        showToast('error', ['Uncaught Error:', e.message, e.filename ? '(' + e.filename + ':' + e.lineno + ')' : '']);
      });

      window.addEventListener('unhandledrejection', function(e) {
        showToast('error', ['Unhandled Promise Rejection:', e.reason]);
      });

      console.log('Console logger & toast system initialized.');
    })();
  </script>

  <script type="text/javascript" src="love.min.js"></script>
  <script type="text/javascript">
    (async function bootBalatro() {
      var statusElement = document.getElementById('status');
      var canvasElement = document.getElementById('canvas');

      console.log('Checking crossOriginIsolated:', window.crossOriginIsolated);
      if (!window.crossOriginIsolated) {
        console.warn('crossOriginIsolated is false. Ensure serve.py sends COOP/COEP headers if SharedArrayBuffer fails.');
      }

      try {
        statusElement.textContent = 'Downloading Balatro.love...';
        console.log('Fetching Balatro.love...');
        var response = await fetch('Balatro.love');
        if (!response.ok) {
          throw new Error('HTTP ' + response.status + ' while fetching Balatro.love');
        }
        var buffer = await response.arrayBuffer();
        var data = new Uint8Array(buffer);
        console.log('Fetched Balatro.love (' + (data.byteLength / (1024 * 1024)).toFixed(2) + ' MB)');

        var Module = {
          arguments: ['./Balatro.love'],
          INITIAL_MEMORY: 268435456,
          print: function(text) {
            console.log(text);
          },
          printErr: function(text) {
            console.error(text);
          },
          canvas: (function() {
            canvasElement.addEventListener('webglcontextlost', function(e) {
              console.error('WebGL context lost!');
              e.preventDefault();
            }, false);
            return canvasElement;
          })(),
          setStatus: function(text) {
            if (!text) {
              statusElement.style.display = 'none';
            } else {
              statusElement.textContent = text;
              console.log('[Status]', text);
            }
          },
          totalDependencies: 0,
          monitorRunDependencies: function(left) {
            this.totalDependencies = Math.max(this.totalDependencies, left);
            Module.setStatus(left ? 'Loading assets... (' + (this.totalDependencies - left) + '/' + this.totalDependencies + ')' : '');
          },
          preRun: [function() {
            console.log('Mounting Balatro.love into virtual filesystem...');
            Module.FS_createDataFile('/', 'Balatro.love', data, true, true, true);
          }],
          onRuntimeInitialized: function() {
            console.log('WebAssembly runtime initialized.');
            statusElement.style.display = 'none';
          }
        };

        if (typeof Love === 'function') {
          console.log('Invoking Love(Module) (2dengine/love.min.js modular runtime)...');
          statusElement.textContent = 'Starting LÖVE 11.5 WebAssembly...';
          await Love(Module);
          statusElement.style.display = 'none';
          console.log('Love(Module) started successfully.');
        } else {
          console.warn('Global Love() factory not found; falling back to window.Module.');
          window.Module = Module;
        }
      } catch (err) {
        statusElement.textContent = 'Boot Error: ' + err.message;
        console.error('Failed to initialize Balatro:', err);
      }
    })();
  </script>
</body>
</html>
EOF

rm -rf "$WEB_SRC_DIR" "$WEBBALATRO_ZIP" "${BUILD_DIR}/web-balatro-src"

echo "=== Build Complete! ==="
echo "1. Native .love archive:      ${BUILD_DIR}/Balatro.love"
echo "2. Packaged Windows build:    ${DIST_WIN_DIR}/Balatro.exe"
echo "3. Centered Web build:        ${DIST_WEB_DIR}/"
