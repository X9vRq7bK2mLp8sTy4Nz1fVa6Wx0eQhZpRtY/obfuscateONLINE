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
    -- It's okay if this fails or returns nil; we'll assume the preset is fine otherwise.
    -- However, since you know you added LuaU here, a failure here is bad.
    io.stderr:write("Warning: Failed to load prometheus/config.lua. Using preset only.")
end

-- 3. Get Environment Variables
local code = os.getenv("USER_CODE") or ""
local preset_name = os.getenv("PROM_PRESET") or "Strong"

-- 4. Merge Custom Config into Preset
-- Start with the chosen preset (e.g., Strong)
local config = Prometheus.Presets[preset_name] or Prometheus.Presets.Strong

-- Explicitly override the LuaVersion from the custom config if loaded
if custom_config and custom_config.LuaVersion then
    config.LuaVersion = custom_config.LuaVersion
    
    -- Merge other settings from config.lua (optional, but good practice)
    for k, v in pairs(custom_config) do
        config[k] = v
    end
end

-- 5. Run Obfuscation
-- Use the merged config
local pipeline = Prometheus.Pipeline:fromConfig(config) 

local success, result = pcall(pipeline.apply, pipeline, code or "")

if not success then
    -- If pcall fails, 'result' contains the error message (this is the key: tostring(result))
    io.stderr:write("Obfuscation Error: " .. tostring(result))
    os.exit(1)
end

-- 6. Print successful result to stdout
io.stdout:write(result)
os.exit(0)
