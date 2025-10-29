-- runner.lua (Updated with MongoDB logic)

-- Configuration Constants
-- Make sure this matches your unique collection name!
local DB_NAME = "obfuscator_db" 
local COLLECTION_NAME = "PrometheusJobs_UXOAOD" -- CHANGE THIS TO YOUR UNIQUE COLLECTION NAME!

-- 1. Setup Prometheus Dependencies (Same as before)
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

-- --- FIX APPLIED HERE ---
-- The client connection must use the connect method on the mongo.client factory.
local client, err = mongo.client:connect(mongo_uri) 
-- If 'client' is nil, the connection failed. 'err' will contain the reason.
if not client then
    io.stderr:write("Error: Could not connect MongoDB client: " .. tostring(err) .. "\n")
    os.exit(1)
end
-- --- END FIX ---

local db = client:get_database(DB_NAME)
local collection = db:get_collection(COLLECTION_NAME)

-- Update the job document with the completed status and the obfuscated code
local success, err = pcall(function()
    collection:update_one(
        { _id = job_id }, -- NOTE: I changed this to use '_id' as per Vercel's trigger.js
        { ['$set'] = { 
            status = "COMPLETED", 
            obfuscatedCode = out, 
            completedAt = os.time() 
        }}
    )
end)

client:close()

if not success then
    io.stderr:write("MongoDB Update Failed: " .. tostring(err) .. "\n")
    os.exit(1)
end

io.stdout:write("Job " .. job_id .. " successfully completed and updated in MongoDB.\n")

-- Do NOT print 'out' here; we are writing to the DB, not stdout.

