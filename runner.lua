-- runner.lua

-- get directory of this file (runner.lua)
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."

-- add src folder to package.path
package.path = package.path .. ";" .. runner_dir .. "/src/?.lua;" .. runner_dir .. "/src/?/init.lua"

-- require Prometheus
local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("prometheus not found in ./src\n")
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
