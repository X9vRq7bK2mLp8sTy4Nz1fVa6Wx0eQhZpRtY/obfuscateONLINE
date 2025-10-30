-- runner.lua (Simplified MongoDB connection for GitHub Actions)

-- Configuration Constants
local DB_NAME = "obfuscator_db" 
local COLLECTION_NAME = "PrometheusJobs_UXOAOD" -- Ensure this is correct

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

-- CRITICAL FIX START: Connect in one robust step and retrieve the collection
local client = mongo.Client(mongo_uri)
local conn = nil
local collection = nil

if client then
    -- Attempt to get connection and collection in the standard way
    local conn_success, conn_or_err = pcall(client.get_connection, client)
    if conn_success and type(conn_or_err) == 'table' then
        conn = conn_or_err
        collection = conn:get_collection(DB_NAME, COLLECTION_NAME)
    else
        io.stderr:write("Error: Failed to get MongoDB connection. Details: " .. tostring(conn_or_err) .. "\n")
    end
else
    io.stderr:write("Error: Could not create MongoDB client (client object is nil).\n")
end

-- Check if we successfully got a collection object before trying to use it
if not collection then
    if client then client:close() end
    os.exit(1)
end

local success, update_err = pcall(function()
    collection:update_one(
        { _id = job_id }, 
        { ['$set'] = { 
            status = "COMPLETED", 
            obfuscatedCode = out, 
            completedAt = os.time() 
        }}
    )
end)

-- Ensure client connection is closed only if it exists
if client then 
    client:close() 
end
-- CRITICAL FIX END

if not success then
    io.stderr:write("MongoDB Update Failed: " .. tostring(update_err) .. "\n")
    os.exit(1)
end

io.stdout:write("Job " .. job_id .. " successfully completed and updated in MongoDB.\n")

