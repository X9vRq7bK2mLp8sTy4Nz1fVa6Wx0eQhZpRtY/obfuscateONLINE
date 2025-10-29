-- runner.lua

-- make package.path relative to runner.lua itself
local runner_dir = debug.getinfo(1).source:match("@?(.*)/runner.lua") or "."
package.path = package.path .. ";" .. runner_dir .. "/src/?.lua;" .. runner_dir .. "/src/?/init.lua"

-- try to require Prometheus
local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("prometheus not found in ./src\n")
    os.exit(1)
end

-- silence logs
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

-- get code and preset from environment variables
local code = os.getenv("USER_CODE") or ""
local preset = os.getenv("PROM_PRESET") or "Strong"

-- create pipeline and apply obfuscation
local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
local out = pipeline:apply(code or "")

-- output the result
io.write(out)
