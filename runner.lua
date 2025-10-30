-- runner.lua (Fixed - Direct Collection Access & C-bound Defensive Update)

-- Configuration Constants
local DB_NAME = "obfuscator_db"
local COLLECTION_NAME = "PrometheusJobs_UXOAOD"

-- 1. Setup Prometheus Dependencies
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."
package.path = package.path .. ";" .. runner_dir .. "/?.lua;" .. runner_dir .. "/?/init.lua"

local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("prometheus.prometheus not found.\n")
    os.exit(1)
end
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

-- 2. Get Environment Variables
local code = os.getenv("USER_CODE") or ""
local preset = os.getenv("PROM_PRESET") or "Strong"
local job_id = os.getenv("JOB_ID") or ""
local mongo_uri = os.getenv("MONGO_URI") or ""

if job_id == "" or mongo_uri == "" then
    io.stderr:write("Error: Missing JOB_ID or MONGO_URI environment variables.\n")
    os.exit(1)
end

-- 3. Run Obfuscation
local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
local out = pipeline:apply(code or "")

-- 4. MongoDB Database Update
local mongo_ok, mongo = pcall(require, "mongo")
if not mongo_ok then
    io.stderr:write("Error: Lua-Mongo driver not found.\n")
    os.exit(1)
end

local collection = nil
local db_error = "Unknown failure during client initialization."
local client = nil

-- connect to collection directly
local ok_coll, coll_obj = pcall(function()
    return mongo.Client(mongo_uri .. "/" .. COLLECTION_NAME)
end)

if ok_coll and (type(coll_obj) == "userdata" or type(coll_obj) == "table") then
    collection = coll_obj
    client = coll_obj
else
    io.stderr:write("MongoDB Collection Init Failed: " .. tostring(coll_obj) .. "\n")
    os.exit(1)
end

-- --- DEFENSIVE UPDATE ---
local selector = { _id = job_id }
local update_doc = { ['$set'] = {
    status = "COMPLETED",
    obfuscatedCode = out,
    completedAt = os.time()
}}

local success, err = pcall(function()
    -- C-bound driver usually exposes a direct 'update' function
    if collection.update then
        collection:update(selector, update_doc, { upsert = false })
    elseif collection.update_one then
        collection:update_one(selector, update_doc)
    else
        error("no supported update method found on collection object")
    end
end)

if not success then
    -- dump metatable for diagnostics
    local mt = getmetatable(collection)
    local methods = "\n(no metatable found)"
    if mt then
        local idx = mt.__index or mt
        local names = {}
        for k,v in pairs(idx) do if type(v) == "function" then names[#names+1] = tostring(k) end end
        table.sort(names)
        methods = "\nAvailable Methods:\n- " .. table.concat(names, "\n- ")
    end
    io.stderr:write("MongoDB Update Failed: " .. tostring(err) .. methods .. "\n")
    if client and type(client.close) == "function" then pcall(client.close, client) end
    os.exit(1)
end

if client and type(client.close) == "function" then pcall(client.close, client) end

io.stdout:write("Job " .. job_id .. " successfully completed and updated in MongoDB.\n")
