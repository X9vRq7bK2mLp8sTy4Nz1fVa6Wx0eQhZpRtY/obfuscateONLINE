-- runner.lua (Fixed to enforce LuaU from config)

-- 1. Setup Prometheus Dependencies
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."
package.path = package.path .. ";" .. runner_dir .. "/?.lua;" .. runner_dir .. "/?/init.lua"

local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("Fatal Error: prometheus.prometheus not found. Check folder name is 'prometheus'.")
    os.exit(1)
end
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

-- 2. Load the custom config.lua
-- This assumes config.lua is located at './prometheus/config.lua' and gets the returned table
local config_ok, custom_config = pcall(require, "prometheus.config") 
if not config_ok then
    io.stderr:write("Fatal Error: Failed to load prometheus/config.lua: " .. tostring(custom_config))
    os.exit(1)
end

-- 3. Get Environment Variables
local code = os.getenv("USER_CODE") or ""
local preset_name = os.getenv("PROM_PRESET") or "Strong"

-- 4. Merge Custom Config into Preset
-- Start with the chosen preset (e.g., Strong)
local config = Prometheus.Presets[preset_name] or Prometheus.Presets.Strong

-- Explicitly override the LuaVersion in the chosen preset with the one from config.lua
-- This ensures 'LuaU' is the target language for obfuscation.
if custom_config and custom_config.LuaVersion then
    config.LuaVersion = custom_config.LuaVersion
    
    -- Also, merge other relevant settings from config.lua if they exist
    for k, v in pairs(custom_config) do
        if k ~= "LuaVersion" then -- Don't overwrite LuaVersion (already done above)
            config[k] = v
        end
    end
end

-- 5. Run Obfuscation
-- Use the merged config
local pipeline = Prometheus.Pipeline:fromConfig(config) 

local success, result = pcall(pipeline.apply, pipeline, code or "")

if not success then
    io.stderr:write("Obfuscation Error: " .. tostring(result))
    os.exit(1)
end

-- 6. Print successful result to stdout
io.stdout:write(result)
os.exit(0)
