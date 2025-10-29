-- runner.lua

-- get directory of this file (runner.lua)
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."

-- THIS IS THE FIX:
-- We add the root directory (where runner.lua is) to the package path.
-- We DO NOT add /src/ anymore.
package.path = package.path .. ";" .. runner_dir .. "/?.lua;" .. runner_dir .. "/?/init.lua"

-- require Prometheus
-- This will now correctly find ./prometheus/prometheus.lua
local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    -- I updated the error message to be more helpful if it fails again
    io.stderr:write("prometheus.prometheus not found. Did you rename /src to /prometheus?\n")
    os.exit(1)
end

-- silence logger
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

-- get code & preset from environment
local code = os.getenv("USER_CODE") or ""
local preset = os.getenv("PROM_PRESET") or "Strong"

-- create pipeline & apply obfuscation
local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
local out = pipeline:apply(code or "")

-- output result
io.write(out)
