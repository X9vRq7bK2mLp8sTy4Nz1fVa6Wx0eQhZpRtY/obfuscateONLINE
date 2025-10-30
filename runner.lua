-- runner.lua (Simplified - No Database)

-- 1. Setup Prometheus Dependencies
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."
package.path = package.path .. ";" .. runner_dir .. "/?.lua;" .. runner_dir .. "/?/init.lua"

local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    -- Print errors to stderr so the GitHub Action can catch them
    io.stderr:write("Fatal Error: prometheus.prometheus not found. Check folder name is 'prometheus'.")
    os.exit(1)
end
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

-- 2. Get Environment Variables
local code = os.getenv("USER_CODE") or ""
local preset = os.getenv("PROM_PRESET") or "Strong"

-- 3. Run Obfuscation
-- We pcall this to catch errors during the obfuscation process
local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)

local success, result = pcall(pipeline.apply, pipeline, code or "")

if not success then
    -- If pcall fails, 'result' contains the error message
    -- Print this to stderr so the .yml file can capture it as an error
    io.stderr:write("Obfuscation Error: " .. tostring(result))
    os.exit(1)
end

-- 4. Print successful result to stdout
-- The GitHub Action workflow will capture this output.
io.stdout:write(result)
os.exit(0)
