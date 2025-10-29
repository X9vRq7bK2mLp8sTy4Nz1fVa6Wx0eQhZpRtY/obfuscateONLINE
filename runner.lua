-- runner_diag.lua (temporary, use to debug)
package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./src/?.lua;./src/prometheus/?.lua"

io.write("cwd: ", (io.popen("pwd"):read("*a") or ""):gsub("%s+$",""), "\n")
io.write("ls -la root:\n")
os.execute("ls -la . || true")
io.write("\nls -la src:\n")
os.execute("ls -la ./src || true")
io.write("\nls -la src/prometheus:\n")
os.execute("ls -la ./src/prometheus || true")
io.write("\npackage.path:\n", package.path, "\n\n")

local ok, mod = pcall(require, "prometheus.prometheus")
if ok then
  io.write("require ok: prometheus loaded\n")
  -- test a simple call if possible (guarded)
  if mod and mod.Pipeline then
    io.write("module has Pipeline key\n")
  end
  os.exit(0)
else
  io.write("require error: ", tostring(mod), "\n")
  -- try fallback: load file directly
  local fpath = "./src/prometheus/prometheus.lua"
  local fh = io.open(fpath, "r")
  if fh then
    io.write("\nfound file at ", fpath, " size=", tostring(fh:seek("end")) , "\n")
    fh:close()
    io.write("attempting dofile fallback...\n")
    local ok2, err2 = pcall(dofile, fpath)
    if ok2 then
      io.write("dofile ok\n")
    else
      io.write("dofile error: ", tostring(err2), "\n")
    end
  else
    io.write("\nfile missing at ", fpath, "\n")
  end
  os.exit(1)
end
