-- runner.lua (Functional - Direct Collection Access & Defensive Update)

-- Configuration Constants
local DB_NAME = "obfuscator_db" -- DB is often encoded in the URI
local COLLECTION_NAME = "PrometheusJobs_UXOAOD" -- Collection name is used here

-- 1. Setup Prometheus Dependencies
local runner_dir = debug.getinfo(1, "S").source:match("@?(.*)/runner.lua") or "."
package.path = package.path .. ";" .. runner_dir .. "/?.lua;" .. runner_dir .. "/?/init.lua"

local ok, Prometheus = pcall(require, "prometheus.prometheus")
if not ok then
    io.stderr:write("prometheus.prometheus not found. Check folder name is 'prometheus'.\n")
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
    io.stderr:write("Error: Lua-Mongo driver not found. Did luarocks install fail?\n")
    os.exit(1)
end

local collection = nil
local db_error = "Unknown failure during client initialization."
local client = nil -- Retain client for optional close call

-- CRITICAL FIX: The constructor returns the collection object directly.
local collection_success, collection_or_err = pcall(function()
    -- This specific driver version appears to return the collection handler directly.
    return mongo.Client(mongo_uri .. "/" .. COLLECTION_NAME)
end)

if collection_success and (type(collection_or_err) == 'table' or type(collection_or_err) == 'userdata') then
    collection = collection_or_err
    client = collection_or_err -- Since we only have one object, use it for close if needed
else
    db_error = "Network/Auth Failure (Client/Collection): " .. tostring(collection_or_err)
end


-- Check if we successfully got a collection object before trying to use it
if not collection then
    io.stderr:write("Fatal: MongoDB Collection Error. Details: " .. db_error .. "\n")
    os.exit(1)
end

-- --- START OF DEFENSIVE UPDATE LOGIC ---
local function try_update(coll, selector, update_doc)
    local ok, res

    -- 1) update_one (py-style / modern drivers)
    ok, res = pcall(function()
        if coll.update_one then return coll:update_one(selector, update_doc) end
    end)
    if ok and res ~= nil then return true, res end

    -- 2) updateOne (camelCase)
    ok, res = pcall(function()
        if coll.updateOne then return coll:updateOne(selector, update_doc) end
    end)
    if ok and res ~= nil then return true, res end

    -- 3) update (older lua drivers: update(selector, update, options))
    ok, res = pcall(function()
        if coll.update then return coll:update(selector, update_doc, { upsert = false }) end
    end)
    if ok and res ~= nil then return true, res end

    return false, "no supported update method succeeded"
end

local selector = { _id = job_id }
local update_doc = { ['$set'] = {
    status = "COMPLETED",
    obfuscatedCode = out,
    completedAt = os.time()
}}

local success, result_or_err = try_update(collection, selector, update_doc)

-- If the update failed, we must dump the methods for final diagnosis
if not success then
    local mt = getmetatable(collection)
    local methods = "\n(no metatable found on collection object)"
    if mt then
        local idx = mt.__index or mt
        local names = {}
        for k,v in pairs(idx) do if type(v) == "function" then names[#names+1] = tostring(k) end end
        table.sort(names)
        methods = "\nAvailable Collection Methods:\n- " .. table.concat(names, "\n- ")
    end
    
    io.stderr:write("MongoDB Update Failed: " .. tostring(result_or_err) .. methods .. "\n")
    
    -- Ensure client connection is closed only if the method exists
    if client and type(client.close) == "function" then pcall(client.close, client) end
    os.exit(1)
end
-- --- END OF DEFENSIVE UPDATE LOGIC ---

-- Ensure client connection is closed only if the method exists
if client and type(client.close) == "function" then 
    pcall(client.close, client) 
end

io.stdout:write("Job " .. job_id .. " successfully completed and updated in MongoDB.\n")

