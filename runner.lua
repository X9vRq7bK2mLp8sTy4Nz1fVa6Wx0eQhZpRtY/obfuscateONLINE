-- runner.lua (project root)
package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("prometheus not found in ./src\n")
    os.exit(1)
end

-- quiet logs
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

local code = os.getenv("USER_CODE") or ""
local preset = os.getenv("PROM_PRESET") or "Strong"

local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
local out = pipeline:apply(code or "")
io.write(out)
